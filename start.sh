#!/bin/bash
# Proof Platform - Quick Start Script
# Run: chmod +x start.sh && ./start.sh

set -e

echo "🔶 Proof Platform - Local Setup"
echo "================================"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js not found. Install from https://nodejs.org (v18+)"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo "❌ Node.js 18+ required. Current: $(node -v)"
    exit 1
fi

echo "✅ Node.js $(node -v)"

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Create .env.local if not exists
if [ ! -f ".env.local" ]; then
    echo "📝 Creating .env.local from example..."
    cp .env.example .env.local
    
    # Enable mock mode by default for quick start
    sed -i.bak 's/NEXT_PUBLIC_MOCK_MODE=false/NEXT_PUBLIC_MOCK_MODE=true/' .env.local
    rm -f .env.local.bak
    
    echo "✅ Created .env.local with MOCK_MODE=true"
fi

# Check for Supabase CLI
if command -v supabase &> /dev/null; then
    echo "✅ Supabase CLI found"
    
    read -p "Start local Supabase? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 Starting Supabase..."
        supabase start
        
        # Update .env.local with local credentials
        SUPABASE_URL=$(supabase status | grep "API URL" | awk '{print $3}')
        ANON_KEY=$(supabase status | grep "anon key" | awk '{print $3}')
        SERVICE_KEY=$(supabase status | grep "service_role key" | awk '{print $3}')
        
        sed -i.bak "s|NEXT_PUBLIC_SUPABASE_URL=.*|NEXT_PUBLIC_SUPABASE_URL=$SUPABASE_URL|" .env.local
        sed -i.bak "s|NEXT_PUBLIC_SUPABASE_ANON_KEY=.*|NEXT_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY|" .env.local
        sed -i.bak "s|SUPABASE_SERVICE_ROLE_KEY=.*|SUPABASE_SERVICE_ROLE_KEY=$SERVICE_KEY|" .env.local
        sed -i.bak 's/NEXT_PUBLIC_MOCK_MODE=true/NEXT_PUBLIC_MOCK_MODE=false/' .env.local
        rm -f .env.local.bak
        
        echo "✅ Supabase running, .env.local updated"
        
        echo "📊 Applying database migrations..."
        supabase db push
    fi
else
    echo "ℹ️  Supabase CLI not found - running in mock mode"
    echo "   Install: npm install -g supabase"
fi

echo ""
echo "🚀 Starting development server..."
echo "================================"
echo ""
npm run dev
