@echo off
setlocal EnableExtensions
chcp 65001 >nul
title put-roadmap-staging launcher
color 0A

cd /d "%~dp0"

echo.
echo ===============================================
echo   PUT ROADMAP STAGING - INSTALL AND RUN
echo ===============================================
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Node.js not found in PATH.
  echo Install Node.js: https://nodejs.org/
  pause
  exit /b 1
)

echo [INFO] Node:
node --version
echo [INFO] npm:
call npm --version
echo.

echo [STEP] Backend dependencies...
pushd "%~dp0backend"
if not exist "node_modules" (
  call npm install
  if errorlevel 1 (
    echo [ERROR] npm install failed in backend
    popd
    pause
    exit /b 1
  )
) else (
  echo [INFO] backend node_modules already exists
)
popd

echo [STEP] Frontend dependencies...
pushd "%~dp0frontend"
if not exist "node_modules" (
  call npm install
  if errorlevel 1 (
    echo [ERROR] npm install failed in frontend
    popd
    pause
    exit /b 1
  )
) else (
  echo [INFO] frontend node_modules already exists
)
popd

echo.
echo [STEP] Starting backend...
start "put-roadmap backend" /D "%~dp0backend" cmd /k "title put-roadmap backend && echo Backend URL: http://127.0.0.1:3012 && npm run dev"

timeout /t 2 /nobreak >nul

echo [STEP] Starting frontend...
start "put-roadmap frontend" /D "%~dp0frontend" cmd /k "title put-roadmap frontend (local only) && echo Frontend URL: http://127.0.0.1:3002 && echo Local only mode enabled && npm run dev"

echo.
echo [OK] Started.
echo Frontend: http://127.0.0.1:3002
echo Backend : http://127.0.0.1:3012
echo Mode    : LOCAL ONLY (no external DuckDNS access)
echo.
echo If something fails, check opened backend/frontend windows.
echo.
pause
