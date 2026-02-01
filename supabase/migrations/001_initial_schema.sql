-- Proof Platform Database Schema
-- Bitcoin Professional Coordination Platform

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================
-- USERS TABLE
-- Both humans and AI agents
-- ============================================
CREATE TABLE public.users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  clerk_id TEXT UNIQUE,
  npub TEXT UNIQUE,
  is_agent BOOLEAN DEFAULT false,
  
  -- Lightning
  lightning_address TEXT,
  nwc_connection TEXT, -- Encrypted NWC connection string
  
  -- Profile
  display_name TEXT NOT NULL,
  username TEXT UNIQUE,
  bio TEXT,
  avatar_url TEXT,
  website TEXT,
  location TEXT,
  timezone TEXT DEFAULT 'UTC',
  
  -- Verification
  nip05_verified BOOLEAN DEFAULT false,
  nip05_identifier TEXT, -- user@domain.com
  email TEXT,
  email_verified BOOLEAN DEFAULT false,
  
  -- Reputation (computed fields)
  reputation_score DECIMAL(5,2) DEFAULT 0.00,
  jobs_completed INTEGER DEFAULT 0,
  jobs_posted INTEGER DEFAULT 0,
  total_earned_sats BIGINT DEFAULT 0,
  total_spent_sats BIGINT DEFAULT 0,
  
  -- Settings
  allows_agent_applications BOOLEAN DEFAULT true,
  public_profile BOOLEAN DEFAULT true,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- USER SKILLS
-- ============================================
CREATE TABLE public.user_skills (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  skill_name TEXT NOT NULL,
  skill_level TEXT CHECK (skill_level IN ('beginner', 'intermediate', 'advanced', 'expert')),
  years_experience INTEGER,
  verified BOOLEAN DEFAULT false,
  verified_by UUID REFERENCES public.users(id),
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, skill_name)
);

-- ============================================
-- JOBS TABLE
-- ============================================
CREATE TABLE public.jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  poster_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  -- Content
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  requirements TEXT[] DEFAULT '{}',
  deliverables TEXT[] DEFAULT '{}',
  
  -- Compensation
  budget_sats BIGINT NOT NULL CHECK (budget_sats > 0),
  payment_type TEXT DEFAULT 'fixed' CHECK (payment_type IN ('fixed', 'hourly', 'milestone')),
  hourly_rate_sats BIGINT, -- For hourly jobs
  
  -- Status
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'in_progress', 'review', 'completed', 'cancelled', 'disputed')),
  
  -- Assignment
  assigned_to UUID REFERENCES public.users(id),
  assigned_at TIMESTAMPTZ,
  
  -- Matching
  required_skills TEXT[] DEFAULT '{}',
  preferred_skills TEXT[] DEFAULT '{}',
  experience_level TEXT CHECK (experience_level IN ('entry', 'intermediate', 'senior', 'expert')),
  location_requirement TEXT DEFAULT 'remote',
  
  -- Visibility
  is_public BOOLEAN DEFAULT true,
  allows_agents BOOLEAN DEFAULT true,
  featured BOOLEAN DEFAULT false,
  
  -- Escrow
  escrow_funded BOOLEAN DEFAULT false,
  escrow_amount_sats BIGINT DEFAULT 0,
  escrow_invoice TEXT,
  escrow_payment_hash TEXT,
  escrow_funded_at TIMESTAMPTZ,
  
  -- Nostr
  nostr_event_id TEXT,
  
  -- Deadlines
  application_deadline TIMESTAMPTZ,
  completion_deadline TIMESTAMPTZ,
  
  -- Timestamps
  published_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PROPOSALS TABLE
-- ============================================
CREATE TABLE public.proposals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
  proposer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  -- Content
  cover_letter TEXT NOT NULL,
  proposed_rate_sats BIGINT,
  estimated_hours INTEGER,
  estimated_days INTEGER,
  
  -- Status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'shortlisted', 'accepted', 'rejected', 'withdrawn')),
  
  -- Timestamps
  submitted_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(job_id, proposer_id)
);

-- ============================================
-- MILESTONES TABLE
-- ============================================
CREATE TABLE public.milestones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
  
  -- Content
  title TEXT NOT NULL,
  description TEXT,
  order_index INTEGER DEFAULT 0,
  amount_sats BIGINT NOT NULL CHECK (amount_sats > 0),
  
  -- Status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'submitted', 'revision_requested', 'approved', 'disputed', 'cancelled')),
  
  -- Escrow
  escrow_locked BOOLEAN DEFAULT false,
  payment_released BOOLEAN DEFAULT false,
  payment_hash TEXT,
  payment_preimage TEXT,
  
  -- Delivery
  deliverable_url TEXT,
  deliverable_notes TEXT,
  submitted_at TIMESTAMPTZ,
  
  -- Review
  reviewer_notes TEXT,
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.users(id),
  
  -- Deadline
  due_date TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- MESSAGES TABLE
-- ============================================
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  job_id UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
  
  -- Content
  content TEXT NOT NULL,
  is_encrypted BOOLEAN DEFAULT false,
  
  -- Status
  read_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- REPUTATION EVENTS TABLE
-- Portable, signed reputation records
-- ============================================
CREATE TABLE public.reputation_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subject_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  author_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  job_id UUID REFERENCES public.jobs(id) ON DELETE SET NULL,
  
  -- Event type
  event_type TEXT NOT NULL CHECK (event_type IN (
    'job_completed', 
    'job_posted',
    'payment_sent', 
    'payment_received', 
    'review_given',
    'review_received',
    'endorsement',
    'badge_earned',
    'verification'
  )),
  
  -- Review data
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  
  -- Amounts
  amount_sats BIGINT,
  
  -- Nostr proof (for portability)
  nostr_event_id TEXT,
  nostr_signature TEXT,
  
  -- Metadata
  metadata JSONB DEFAULT '{}',
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PAYMENTS TABLE
-- ============================================
CREATE TABLE public.payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  from_user_id UUID REFERENCES public.users(id),
  to_user_id UUID REFERENCES public.users(id),
  job_id UUID REFERENCES public.jobs(id),
  milestone_id UUID REFERENCES public.milestones(id),
  
  -- Amount
  amount_sats BIGINT NOT NULL CHECK (amount_sats > 0),
  
  -- Type
  payment_type TEXT NOT NULL CHECK (payment_type IN (
    'escrow_fund',
    'milestone_release',
    'job_completion',
    'tip',
    'referral_bonus',
    'platform_fee'
  )),
  
  -- Lightning
  invoice TEXT,
  payment_hash TEXT,
  payment_preimage TEXT,
  
  -- Status
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  paid_at TIMESTAMPTZ,
  
  -- Metadata
  metadata JSONB DEFAULT '{}'
);

-- ============================================
-- REFERRALS TABLE
-- ============================================
CREATE TABLE public.referrals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  referrer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  referred_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  -- Tracking
  referral_code TEXT UNIQUE,
  
  -- Rewards
  referrer_reward_sats BIGINT DEFAULT 0,
  referred_reward_sats BIGINT DEFAULT 0,
  reward_paid BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(referrer_id, referred_id)
);

-- ============================================
-- NOTIFICATIONS TABLE
-- ============================================
CREATE TABLE public.notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  
  -- Content
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  
  -- Related entities
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE,
  proposal_id UUID REFERENCES public.proposals(id) ON DELETE CASCADE,
  message_id UUID REFERENCES public.messages(id) ON DELETE CASCADE,
  
  -- Status
  read_at TIMESTAMPTZ,
  
  -- Link
  action_url TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- VECTOR EMBEDDINGS FOR SEMANTIC SEARCH
-- ============================================
CREATE TABLE public.job_embeddings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  job_id UUID REFERENCES public.jobs(id) ON DELETE CASCADE UNIQUE,
  embedding vector(1536),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.user_embeddings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  embedding vector(1536),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES
-- ============================================

-- Users
CREATE INDEX idx_users_clerk ON public.users(clerk_id);
CREATE INDEX idx_users_npub ON public.users(npub);
CREATE INDEX idx_users_username ON public.users(username);
CREATE INDEX idx_users_reputation ON public.users(reputation_score DESC);

-- Jobs
CREATE INDEX idx_jobs_poster ON public.jobs(poster_id);
CREATE INDEX idx_jobs_status ON public.jobs(status);
CREATE INDEX idx_jobs_assigned ON public.jobs(assigned_to);
CREATE INDEX idx_jobs_skills ON public.jobs USING GIN(required_skills);
CREATE INDEX idx_jobs_created ON public.jobs(created_at DESC);
CREATE INDEX idx_jobs_budget ON public.jobs(budget_sats);
CREATE INDEX idx_jobs_search ON public.jobs USING GIN(to_tsvector('english', title || ' ' || description));

-- Proposals
CREATE INDEX idx_proposals_job ON public.proposals(job_id);
CREATE INDEX idx_proposals_proposer ON public.proposals(proposer_id);
CREATE INDEX idx_proposals_status ON public.proposals(status);

-- Messages
CREATE INDEX idx_messages_recipient ON public.messages(recipient_id, read_at NULLS FIRST);
CREATE INDEX idx_messages_sender ON public.messages(sender_id);
CREATE INDEX idx_messages_job ON public.messages(job_id);

-- Reputation
CREATE INDEX idx_reputation_subject ON public.reputation_events(subject_id);
CREATE INDEX idx_reputation_author ON public.reputation_events(author_id);
CREATE INDEX idx_reputation_type ON public.reputation_events(event_type);

-- Payments
CREATE INDEX idx_payments_from ON public.payments(from_user_id);
CREATE INDEX idx_payments_to ON public.payments(to_user_id);
CREATE INDEX idx_payments_job ON public.payments(job_id);
CREATE INDEX idx_payments_status ON public.payments(status);

-- Notifications
CREATE INDEX idx_notifications_user ON public.notifications(user_id, read_at NULLS FIRST);

-- Vector search
CREATE INDEX idx_job_embeddings_vector ON public.job_embeddings 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_user_embeddings_vector ON public.user_embeddings 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_jobs_updated_at BEFORE UPDATE ON public.jobs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_proposals_updated_at BEFORE UPDATE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_milestones_updated_at BEFORE UPDATE ON public.milestones
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Update user reputation on reputation event
CREATE OR REPLACE FUNCTION update_user_reputation()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.users
  SET 
    reputation_score = (
      SELECT COALESCE(AVG(rating), 0)
      FROM public.reputation_events
      WHERE subject_id = NEW.subject_id AND rating IS NOT NULL
    ),
    jobs_completed = (
      SELECT COUNT(*)
      FROM public.reputation_events
      WHERE subject_id = NEW.subject_id AND event_type = 'job_completed'
    ),
    total_earned_sats = (
      SELECT COALESCE(SUM(amount_sats), 0)
      FROM public.reputation_events
      WHERE subject_id = NEW.subject_id AND event_type = 'payment_received'
    )
  WHERE id = NEW.subject_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_reputation AFTER INSERT ON public.reputation_events
  FOR EACH ROW EXECUTE FUNCTION update_user_reputation();

-- Semantic search function
CREATE OR REPLACE FUNCTION search_jobs_semantic(
  query_embedding vector(1536),
  match_threshold float DEFAULT 0.7,
  match_count int DEFAULT 10
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  description TEXT,
  budget_sats BIGINT,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    j.id,
    j.title,
    j.description,
    j.budget_sats,
    1 - (je.embedding <=> query_embedding) as similarity
  FROM public.jobs j
  JOIN public.job_embeddings je ON j.id = je.job_id
  WHERE j.status = 'open'
    AND 1 - (je.embedding <=> query_embedding) > match_threshold
  ORDER BY je.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users: Public profiles readable, own profile editable
CREATE POLICY "Public profiles are viewable by everyone"
  ON public.users FOR SELECT
  USING (public_profile = true);

CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  USING (auth.uid()::text = clerk_id);

-- Jobs: Public jobs readable, poster can manage
CREATE POLICY "Public jobs are viewable by everyone"
  ON public.jobs FOR SELECT
  USING (is_public = true OR poster_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));

CREATE POLICY "Users can create jobs"
  ON public.jobs FOR INSERT
  WITH CHECK (poster_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));

CREATE POLICY "Posters can update their jobs"
  ON public.jobs FOR UPDATE
  USING (poster_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));

-- Proposals: Visible to proposer and job poster
CREATE POLICY "Proposals visible to involved parties"
  ON public.proposals FOR SELECT
  USING (
    proposer_id IN (SELECT id FROM public.users WHERE clerk_id = auth.uid()::text)
    OR job_id IN (
      SELECT id FROM public.jobs WHERE poster_id IN (
        SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
      )
    )
  );

CREATE POLICY "Users can submit proposals"
  ON public.proposals FOR INSERT
  WITH CHECK (proposer_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));

-- Messages: Only sender and recipient
CREATE POLICY "Messages visible to participants"
  ON public.messages FOR SELECT
  USING (
    sender_id IN (SELECT id FROM public.users WHERE clerk_id = auth.uid()::text)
    OR recipient_id IN (SELECT id FROM public.users WHERE clerk_id = auth.uid()::text)
  );

CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT
  WITH CHECK (sender_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));

-- Notifications: Only own
CREATE POLICY "Users see own notifications"
  ON public.notifications FOR SELECT
  USING (user_id IN (
    SELECT id FROM public.users WHERE clerk_id = auth.uid()::text
  ));
