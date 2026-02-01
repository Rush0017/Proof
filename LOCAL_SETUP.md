# Proof Platform - Local Setup Guide

## Prerequisites

```bash
# Required
node -v   # 18+ required
npm -v    # 9+ required

# Optional (for full features)
docker -v # For local Supabase
```

## Quick Start (5 minutes)

### 1. Install Dependencies

```bash
cd proof
npm install
```

### 2. Create Environment File

```bash
cp .env.example .env.local
```

### 3. Start Local Supabase (Option A - Recommended)

```bash
# Install Supabase CLI
npm install -g supabase

# Start local Supabase (runs PostgreSQL + Auth + Realtime)
supabase start

# This outputs your local credentials - copy them to .env.local
```

### 4. Or Use Mock Mode (Option B - No Database)

Edit `.env.local`:
```
NEXT_PUBLIC_MOCK_MODE=true
```

### 5. Run Development Server

```bash
npm run dev
```

Open http://localhost:3000

---

## Full Setup (Production-like)

### Supabase Setup

1. Start local Supabase:
```bash
supabase start
```

2. Apply migrations:
```bash
supabase db push
```

3. Copy credentials from `supabase start` output to `.env.local`:
```
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<from output>
SUPABASE_SERVICE_ROLE_KEY=<from output>
```

### Clerk Setup (Auth)

1. Create free account at https://clerk.com
2. Create new application
3. Copy keys to `.env.local`:
```
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_test_...
CLERK_SECRET_KEY=sk_test_...
```

### LNbits Setup (Lightning Payments)

Option A: Use legend.lnbits.com (free, custodial)
1. Go to https://legend.lnbits.com
2. Create wallet
3. Copy Admin Key and Invoice Key

Option B: Self-hosted (non-custodial)
```bash
docker run -d -p 5000:5000 lnbits/lnbits
```

Add to `.env.local`:
```
LNBITS_URL=https://legend.lnbits.com
LNBITS_ADMIN_KEY=<your-admin-key>
LNBITS_INVOICE_KEY=<your-invoice-key>
```

---

## Environment Variables Reference

```bash
# App
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXT_PUBLIC_MOCK_MODE=false

# Supabase
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Clerk (optional - for auth)
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=
CLERK_SECRET_KEY=
NEXT_PUBLIC_CLERK_SIGN_IN_URL=/sign-in
NEXT_PUBLIC_CLERK_SIGN_UP_URL=/sign-up
NEXT_PUBLIC_CLERK_AFTER_SIGN_IN_URL=/dashboard
NEXT_PUBLIC_CLERK_AFTER_SIGN_UP_URL=/onboarding

# LNbits (optional - for payments)
LNBITS_URL=https://legend.lnbits.com
LNBITS_ADMIN_KEY=
LNBITS_INVOICE_KEY=

# Nostr (optional - auto-generated if not set)
NOSTR_PRIVATE_KEY=
NOSTR_RELAYS=wss://relay.damus.io,wss://nos.lol

# L402 (auto-generated if not set)
MACAROON_SECRET=
```

---

## Troubleshooting

### "Module not found" errors
```bash
rm -rf node_modules package-lock.json
npm install
```

### Supabase won't start
```bash
supabase stop
docker system prune -f
supabase start
```

### Port 3000 in use
```bash
npm run dev -- -p 3001
```

### Clerk redirect errors
Make sure URLs in Clerk dashboard match your localhost

---

## Development Workflow

```bash
# Start everything
supabase start
npm run dev

# Reset database
npm run db:reset

# Generate TypeScript types from database
npm run db:generate

# Run linter
npm run lint
```
