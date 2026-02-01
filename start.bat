@echo off
REM Proof Platform - Quick Start Script (Windows)
REM Run: start.bat

echo.
echo 🔶 Proof Platform - Local Setup
echo ================================

REM Check Node.js
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ❌ Node.js not found. Install from https://nodejs.org ^(v18+^)
    pause
    exit /b 1
)

for /f "tokens=1 delims=v" %%a in ('node -v') do set NODE_VER=%%a
echo ✅ Node.js installed

REM Install dependencies
if not exist "node_modules" (
    echo 📦 Installing dependencies...
    call npm install
)

REM Create .env.local if not exists
if not exist ".env.local" (
    echo 📝 Creating .env.local from example...
    copy .env.example .env.local
    
    REM Enable mock mode
    powershell -Command "(Get-Content .env.local) -replace 'NEXT_PUBLIC_MOCK_MODE=false', 'NEXT_PUBLIC_MOCK_MODE=true' | Set-Content .env.local"
    
    echo ✅ Created .env.local with MOCK_MODE=true
)

echo.
echo 🚀 Starting development server...
echo ================================
echo.
echo Open http://localhost:3000 in your browser
echo.
call npm run dev
