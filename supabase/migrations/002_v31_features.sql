-- Proof Platform v3.1 Migration
-- Adds: Non-custodial escrow, disputes, arbiters, recovery system, oracle registry

-- ============================================
-- ESCROW SYSTEM (Non-Custodial)
-- ============================================
CREATE TABLE IF NOT EXISTS public.escrows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE UNIQUE,
  
  -- Type (auto-selected based on duration/amount)
  escrow_type TEXT NOT NULL CHECK (escrow_type IN ('hodl_invoice', 'dlc', 'streaming')),
  
  -- HODL INVOICE FIELDS
  hodl_payment_hash TEXT,
  hodl_preimage_encrypted TEXT,
  hodl_preimage_unlock_at TIMESTAMPTZ,
  hodl_invoice TEXT,
  hodl_expires_at TIMESTAMPTZ,
  
  -- DLC FIELDS
  dlc_contract_id TEXT,
  dlc_funding_txid TEXT,
  dlc_funding_vout INTEGER,
  dlc_oracle_pubkeys TEXT[],
  dlc_oracle_threshold INTEGER DEFAULT 2,
  dlc_oracle_count INTEGER DEFAULT 3,
  dlc_outcomes JSONB,
  dlc_unilateral_timeout TIMESTAMPTZ,
  dlc_abandonment_timeout TIMESTAMPTZ,
  
  -- STREAMING FIELDS
  streaming_sats_per_hour INTEGER,
  streaming_max_daily_sats BIGINT,
  streaming_nwc_connection_id TEXT,
  streaming_budget_remaining_sats BIGINT,
  streaming_total_streamed_sats BIGINT DEFAULT 0,
  streaming_last_payment_at TIMESTAMPTZ,
  
  -- COMMON FIELDS
  amount_sats BIGINT NOT NULL,
  platform_fee_sats BIGINT NOT NULL,
  
  status TEXT DEFAULT 'pending' CHECK (status IN (
    'pending', 'funded', 'releasing', 'released', 
    'refunded', 'disputed', 'timeout_unilateral', 'timeout_abandoned'
  )),
  
  funded_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  work_submitted_at TIMESTAMPTZ,
  auto_release_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_escrows_job ON escrows(job_id);
CREATE INDEX IF NOT EXISTS idx_escrows_status ON escrows(status);
CREATE INDEX IF NOT EXISTS idx_escrows_auto_release ON escrows(auto_release_at) WHERE status = 'funded';

-- ============================================
-- ORACLE REGISTRY
-- ============================================
CREATE TABLE IF NOT EXISTS public.oracle_registry (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  name TEXT NOT NULL,
  npub TEXT UNIQUE NOT NULL,
  pubkey_hex TEXT UNIQUE NOT NULL,
  
  jurisdiction TEXT NOT NULL,
  organization_type TEXT NOT NULL CHECK (organization_type IN ('proof', 'exchange', 'community', 'independent')),
  
  attestation_endpoint TEXT NOT NULL,
  
  stake_amount_sats BIGINT DEFAULT 0,
  stake_locked_until TIMESTAMPTZ,
  
  total_attestations INTEGER DEFAULT 0,
  disputed_attestations INTEGER DEFAULT 0,
  avg_response_time_ms INTEGER,
  
  is_active BOOLEAN DEFAULT true,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- DLC ATTESTATIONS
CREATE TABLE IF NOT EXISTS public.dlc_attestations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  escrow_id UUID REFERENCES public.escrows(id) ON DELETE CASCADE,
  
  oracle_pubkey TEXT NOT NULL,
  oracle_name TEXT,
  
  outcome TEXT NOT NULL,
  attestation_signature TEXT,
  
  attested_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(escrow_id, oracle_pubkey)
);

-- ============================================
-- ARBITERS
-- ============================================
CREATE TABLE IF NOT EXISTS public.arbiters (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  
  reputation_score DECIMAL(5,2) NOT NULL CHECK (reputation_score >= 4.5),
  jobs_completed INTEGER NOT NULL CHECK (jobs_completed >= 10),
  total_volume_sats BIGINT NOT NULL CHECK (total_volume_sats >= 10000000),
  
  bond_amount_sats BIGINT DEFAULT 100000,
  bond_locked_until TIMESTAMPTZ,
  
  disputes_handled INTEGER DEFAULT 0,
  disputes_appealed INTEGER DEFAULT 0,
  appeal_overturn_rate DECIMAL(3,2) DEFAULT 0,
  
  is_active BOOLEAN DEFAULT true,
  specialties TEXT[],
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ARBITER BONDS
CREATE TABLE IF NOT EXISTS public.arbiter_bonds (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  arbiter_id UUID REFERENCES public.arbiters(id) ON DELETE CASCADE UNIQUE,
  
  amount_sats BIGINT NOT NULL,
  original_amount_sats BIGINT,
  slashed_amount_sats BIGINT DEFAULT 0,
  
  dlc_contract_id TEXT,
  dlc_funding_txid TEXT,
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'slashing', 'depleted', 'released')),
  
  funded_at TIMESTAMPTZ,
  locked_until TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- DISPUTES
-- ============================================
CREATE TABLE IF NOT EXISTS public.disputes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
  milestone_id UUID REFERENCES public.milestones(id),
  escrow_id UUID REFERENCES public.escrows(id),
  
  raised_by UUID REFERENCES public.users(id),
  against UUID REFERENCES public.users(id),
  
  arbiter_id UUID REFERENCES public.arbiters(id),
  arbiter_assigned_at TIMESTAMPTZ,
  
  reason TEXT NOT NULL CHECK (reason IN (
    'work_not_delivered', 'work_not_as_described', 'payment_not_released',
    'communication_breakdown', 'scope_dispute', 'other'
  )),
  description TEXT NOT NULL,
  evidence_urls TEXT[],
  
  status TEXT DEFAULT 'open' CHECK (status IN (
    'open', 'under_review', 'awaiting_response', 'resolved', 'appealed', 'final'
  )),
  
  resolution TEXT CHECK (resolution IN ('full_to_worker', 'full_to_client', 'split', 'cancelled')),
  resolution_split_percent INTEGER CHECK (resolution_split_percent BETWEEN 0 AND 100),
  resolution_notes TEXT,
  
  response_deadline TIMESTAMPTZ,
  escalation_deadline TIMESTAMPTZ,
  
  appealed_by UUID REFERENCES public.users(id),
  appeal_reason TEXT,
  appeal_panel_ids UUID[],
  appeal_resolution TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_disputes_job ON disputes(job_id);
CREATE INDEX IF NOT EXISTS idx_disputes_status ON disputes(status);

-- ARBITER SLASHING EVENTS
CREATE TABLE IF NOT EXISTS public.arbiter_slashing_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  arbiter_id UUID REFERENCES public.arbiters(id),
  dispute_id UUID REFERENCES public.disputes(id),
  
  reason TEXT NOT NULL CHECK (reason IN (
    'appeal_overturned', 'timeout_missed', 'conflict_of_interest', 'collusion_detected'
  )),
  
  slash_amount_sats BIGINT NOT NULL,
  slash_executed BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- RECOVERY SYSTEM (Shamir + Time-Lock)
-- ============================================
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS key_storage_method TEXT DEFAULT 'shamir' 
  CHECK (key_storage_method IN ('shamir', 'hardware', 'passphrase', 'custodial_agent'));
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS shamir_share_locations JSONB;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS shamir_threshold INTEGER DEFAULT 3;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS shamir_total_shares INTEGER DEFAULT 5;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS recovery_phone TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS recovery_phone_verified BOOLEAN DEFAULT false;

-- RECOVERY REQUESTS
CREATE TABLE IF NOT EXISTS public.recovery_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  unlock_at TIMESTAMPTZ NOT NULL,
  
  shares_collected INTEGER DEFAULT 0,
  shares_required INTEGER NOT NULL,
  share_sources JSONB DEFAULT '[]',
  
  status TEXT DEFAULT 'pending' CHECK (status IN (
    'pending', 'collecting', 'completed', 'cancelled', 'expired'
  )),
  
  cancelled_by UUID REFERENCES public.users(id),
  cancellation_reason TEXT,
  
  completed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RECOVERY ALERTS
CREATE TABLE IF NOT EXISTS public.recovery_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recovery_request_id UUID REFERENCES public.recovery_requests(id) ON DELETE CASCADE,
  
  share_holder_npub TEXT,
  share_holder_email TEXT,
  share_holder_phone TEXT,
  
  alert_type TEXT NOT NULL,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  
  response TEXT CHECK (response IN ('acknowledged', 'objected', 'no_response')),
  response_at TIMESTAMPTZ,
  objection_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- AGENT CAPABILITIES & SPENDING LIMITS
-- ============================================
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS agent_verification_level TEXT 
  CHECK (agent_verification_level IN ('self_declared', 'delegated', 'tee_attested', 'code_audited'));
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS agent_operator_npub TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS delegation_token TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS delegation_scope JSONB;

CREATE TABLE IF NOT EXISTS public.agent_capabilities (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  capability TEXT NOT NULL CHECK (capability IN (
    'browse_jobs', 'submit_proposals', 'accept_jobs', 'decline_jobs', 'submit_work',
    'view_balance', 'receive_payments', 'send_payments', 'create_invoices',
    'send_messages', 'read_messages', 'raise_dispute', 'respond_dispute',
    'update_profile', 'manage_skills'
  )),
  
  daily_limit INTEGER,
  requires_human_approval BOOLEAN DEFAULT false,
  max_value_sats BIGINT,
  
  max_single_payment_sats BIGINT DEFAULT 100000,
  max_daily_payment_sats BIGINT DEFAULT 1000000,
  requires_human_approval_above_sats BIGINT DEFAULT 500000,
  
  granted_by UUID REFERENCES public.users(id),
  granted_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  
  UNIQUE(agent_id, capability)
);

CREATE TABLE IF NOT EXISTS public.agent_daily_spend (
  agent_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  spend_date DATE DEFAULT CURRENT_DATE,
  total_spent_sats BIGINT DEFAULT 0,
  transaction_count INTEGER DEFAULT 0,
  daily_limit_sats BIGINT,
  PRIMARY KEY (agent_id, spend_date)
);

CREATE TABLE IF NOT EXISTS public.agent_approval_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id UUID REFERENCES public.users(id),
  operator_id UUID REFERENCES public.users(id),
  
  action_type TEXT NOT NULL,
  action_details JSONB NOT NULL,
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'expired')),
  
  responded_by UUID REFERENCES public.users(id),
  response_notes TEXT,
  responded_at TIMESTAMPTZ,
  
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours',
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- RATE LIMITING
-- ============================================
CREATE TABLE IF NOT EXISTS public.rate_limits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  endpoint_pattern TEXT NOT NULL,
  
  anonymous_rpm INTEGER,
  authenticated_rpm INTEGER,
  premium_rpm INTEGER,
  agent_rpm INTEGER,
  
  burst_size INTEGER DEFAULT 10,
  refill_rate DECIMAL DEFAULT 1.0,
  
  l402_price_sats INTEGER,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.rate_limits (endpoint_pattern, anonymous_rpm, authenticated_rpm, agent_rpm, l402_price_sats) VALUES
('/v1/jobs', 30, 120, 300, 10),
('/v1/jobs/*', 60, 240, 600, 5),
('/v1/proposals', 10, 60, 120, 50),
('/v1/search', 10, 60, 120, 20),
('/v1/messages', 20, 120, 30, 100)
ON CONFLICT DO NOTHING;

-- ============================================
-- WEBHOOKS
-- ============================================
CREATE TABLE IF NOT EXISTS public.webhook_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  url TEXT NOT NULL,
  secret TEXT NOT NULL,
  
  events TEXT[] NOT NULL,
  
  is_active BOOLEAN DEFAULT true,
  
  consecutive_failures INTEGER DEFAULT 0,
  total_deliveries INTEGER DEFAULT 0,
  total_failures INTEGER DEFAULT 0,
  last_success_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  disabled_at TIMESTAMPTZ,
  disabled_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.webhook_deliveries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subscription_id UUID REFERENCES public.webhook_subscriptions(id) ON DELETE CASCADE,
  
  event_type TEXT NOT NULL,
  event_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  
  attempt INTEGER DEFAULT 1,
  max_attempts INTEGER DEFAULT 6,
  
  next_attempt_at TIMESTAMPTZ,
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'failed', 'dead')),
  response_status INTEGER,
  response_body TEXT,
  response_time_ms INTEGER,
  
  delivered_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- AUDIT LOG
-- ============================================
CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  user_id UUID REFERENCES public.users(id),
  agent_id UUID REFERENCES public.users(id),
  ip_address INET,
  user_agent TEXT,
  
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  
  old_value JSONB,
  new_value JSONB,
  changed_fields TEXT[],
  
  request_id TEXT,
  endpoint TEXT,
  http_method TEXT,
  
  data_sensitivity TEXT CHECK (data_sensitivity IN ('public', 'internal', 'sensitive', 'pii')),
  retention_until TIMESTAMPTZ,
  anonymized_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON audit_log(entity_type, entity_id, created_at);

-- ============================================
-- SKILLS TAXONOMY
-- ============================================
CREATE TABLE IF NOT EXISTS public.skills (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  name TEXT UNIQUE NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  
  category TEXT NOT NULL CHECK (category IN (
    'blockchain', 'programming', 'design', 'writing', 'marketing', 'business', 'legal', 'other'
  )),
  subcategory TEXT,
  
  aliases TEXT[] DEFAULT '{}',
  
  description TEXT,
  icon_url TEXT,
  
  job_count INTEGER DEFAULT 0,
  user_count INTEGER DEFAULT 0,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.skills (name, slug, category, aliases) VALUES
('Lightning Network', 'lightning-network', 'blockchain', ARRAY['LN', 'Lightning', '⚡', 'BOLT']),
('Bitcoin', 'bitcoin', 'blockchain', ARRAY['BTC', '₿', 'Bitcoin Core']),
('Nostr', 'nostr', 'blockchain', ARRAY['NOSTR', 'NIP']),
('Rust', 'rust', 'programming', ARRAY['Rust Lang', 'rustlang']),
('Go', 'go', 'programming', ARRAY['Golang', 'Go Lang']),
('TypeScript', 'typescript', 'programming', ARRAY['TS', 'TSX']),
('React', 'react', 'programming', ARRAY['ReactJS', 'React.js']),
('LND', 'lnd', 'blockchain', ARRAY['Lightning Network Daemon']),
('CLN', 'cln', 'blockchain', ARRAY['Core Lightning', 'c-lightning']),
('LDK', 'ldk', 'blockchain', ARRAY['Lightning Dev Kit']),
('UI/UX', 'ui-ux', 'design', ARRAY['User Interface', 'User Experience']),
('Figma', 'figma', 'design', ARRAY[]),
('Writing', 'writing', 'writing', ARRAY['Content Writing', 'Technical Writing']),
('MCP', 'mcp', 'programming', ARRAY['Model Context Protocol'])
ON CONFLICT (slug) DO NOTHING;

-- ============================================
-- JOB TEMPLATES
-- ============================================
CREATE TABLE IF NOT EXISTS public.job_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  category TEXT NOT NULL,
  
  title_template TEXT NOT NULL,
  description_template TEXT NOT NULL,
  
  suggested_skills UUID[],
  suggested_budget_range INT4RANGE,
  suggested_duration_days INT4RANGE,
  
  usage_count INTEGER DEFAULT 0,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.job_templates (name, slug, category, title_template, description_template, suggested_budget_range, suggested_duration_days) VALUES
('Lightning Integration', 'lightning-integration', 'development',
 'Lightning Network Integration for [Your Project]',
 E'## Overview\nIntegrate Lightning Network payments into [describe your application].\n\n## Requirements\n- [Specific requirements]\n\n## Deliverables\n- Working Lightning payment flow\n- Documentation\n- Tests',
 '[500000, 5000000)', '[7, 30)'),
('Nostr Client Feature', 'nostr-client-feature', 'development',
 '[Feature Name] for Nostr Client',
 E'## Overview\nBuild [feature] for our Nostr client.\n\n## Requirements\n- Must follow Nostr NIPs\n- [Other requirements]\n\n## Deliverables\n- Feature implementation\n- NIP compliance documentation',
 '[200000, 2000000)', '[7, 21)'),
('Bitcoin Content Writing', 'bitcoin-content', 'content',
 '[Topic] Article/Guide/Tutorial',
 E'## Overview\nWrite [type of content] about [topic].\n\n## Requirements\n- [Word count, style, etc.]\n- Technically accurate\n\n## Deliverables\n- Written content in Markdown\n- Any supporting graphics',
 '[50000, 500000)', '[3, 14)')
ON CONFLICT (slug) DO NOTHING;

-- ============================================
-- EMBEDDING QUEUE
-- ============================================
CREATE TABLE IF NOT EXISTS public.embedding_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  operation TEXT NOT NULL,
  
  status TEXT DEFAULT 'pending',
  
  locked_by TEXT,
  locked_at TIMESTAMPTZ,
  heartbeat_at TIMESTAMPTZ,
  
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 5,
  last_error TEXT,
  
  dead_lettered_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_embedding_queue_pending ON embedding_queue(created_at) WHERE status = 'pending';

-- ============================================
-- GDPR: DELETION REQUESTS
-- ============================================
CREATE TABLE IF NOT EXISTS public.deletion_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id),
  
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  
  verified_at TIMESTAMPTZ,
  verification_method TEXT,
  
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'processing', 'completed', 'blocked')),
  blocked_reason TEXT,
  
  completed_at TIMESTAMPTZ,
  data_export_url TEXT,
  export_expires_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- ADD AUTO-CLOSE TO JOBS
-- ============================================
ALTER TABLE public.jobs ADD COLUMN IF NOT EXISTS auto_close_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '90 days';

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Select escrow type based on duration and amount
CREATE OR REPLACE FUNCTION select_escrow_type(
  duration_hours INTEGER,
  amount_sats BIGINT,
  is_recurring BOOLEAN
)
RETURNS TEXT AS $$
BEGIN
  IF is_recurring THEN RETURN 'streaming'; END IF;
  IF duration_hours < 24 THEN RETURN 'hodl_invoice'; END IF;
  RETURN 'dlc';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Determine oracle config based on amount
CREATE OR REPLACE FUNCTION determine_oracle_config(amount_sats BIGINT)
RETURNS TABLE(oracle_count INTEGER, threshold INTEGER) AS $$
BEGIN
  IF amount_sats >= 100000000 THEN RETURN QUERY SELECT 7, 5;
  ELSIF amount_sats >= 10000000 THEN RETURN QUERY SELECT 5, 3;
  ELSE RETURN QUERY SELECT 3, 2;
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Check if DLC can settle
CREATE OR REPLACE FUNCTION can_settle_dlc(escrow_uuid UUID)
RETURNS TABLE(can_settle BOOLEAN, outcome TEXT, attestation_count INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*) >= (SELECT dlc_oracle_threshold FROM escrows WHERE id = escrow_uuid),
    da.outcome,
    COUNT(*)::INTEGER
  FROM dlc_attestations da
  WHERE da.escrow_id = escrow_uuid
  GROUP BY da.outcome
  HAVING COUNT(*) >= (SELECT dlc_oracle_threshold FROM escrows WHERE id = escrow_uuid)
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Claim embedding job (with SKIP LOCKED)
CREATE OR REPLACE FUNCTION claim_embedding_job(p_worker_id TEXT)
RETURNS TABLE(job_id UUID, entity_type TEXT, entity_id UUID, operation TEXT) AS $$
BEGIN
  RETURN QUERY
  UPDATE embedding_queue eq
  SET status = 'processing', locked_by = p_worker_id, locked_at = NOW(), heartbeat_at = NOW()
  WHERE eq.id = (
    SELECT id FROM embedding_queue
    WHERE status = 'pending' AND attempts < max_attempts
    ORDER BY created_at
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  )
  RETURNING eq.id, eq.entity_type, eq.entity_id, eq.operation;
END;
$$ LANGUAGE plpgsql;

-- Compute reputation with confidence
CREATE OR REPLACE FUNCTION compute_reputation_v3(user_uuid UUID)
RETURNS TABLE(score DECIMAL(5,2), confidence DECIMAL(3,2)) AS $$
DECLARE
  base_score DECIMAL;
  review_count INTEGER;
  stake_factor DECIMAL;
  graph_factor DECIMAL;
  recency_factor DECIMAL;
  final_score DECIMAL;
  final_confidence DECIMAL;
BEGIN
  SELECT (10 * 3.0 + COALESCE(SUM(rating), 0)) / (10 + COUNT(*)), COUNT(*)
  INTO base_score, review_count
  FROM reputation_events
  WHERE subject_id = user_uuid AND event_type = 'review'
    AND created_at > NOW() - INTERVAL '2 years' AND weight > 0.5;
  
  SELECT LEAST(LN(GREATEST(total_earned_sats + total_spent_sats, 1)) / 40, 0.5)
  INTO stake_factor FROM users WHERE id = user_uuid;
  
  SELECT LEAST(COUNT(*) * 0.05, 0.3) INTO graph_factor
  FROM reputation_events re JOIN users endorser ON re.author_id = endorser.id
  WHERE re.subject_id = user_uuid AND re.event_type = 'endorsement'
    AND endorser.reputation_score >= 4.5 AND re.created_at > NOW() - INTERVAL '1 year';
  
  SELECT CASE
    WHEN MAX(created_at) > NOW() - INTERVAL '7 days' THEN 0.2
    WHEN MAX(created_at) > NOW() - INTERVAL '30 days' THEN 0.1
    ELSE 0
  END INTO recency_factor FROM reputation_events WHERE subject_id = user_uuid;
  
  final_score := GREATEST(0, LEAST(5,
    COALESCE(base_score, 3) + COALESCE(stake_factor, 0) + COALESCE(graph_factor, 0) + COALESCE(recency_factor, 0)
  ));
  
  final_confidence := LEAST(1.0,
    (COALESCE(review_count, 0)::decimal / 20) * 0.5 +
    (COALESCE(stake_factor, 0) / 0.5) * 0.3 +
    (COALESCE(graph_factor, 0) / 0.3) * 0.2
  );
  
  RETURN QUERY SELECT ROUND(final_score, 2), ROUND(final_confidence, 2);
END;
$$ LANGUAGE plpgsql;
