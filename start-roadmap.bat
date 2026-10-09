@echo off
setlocal EnableExtensions
chcp 65001 >nul
title put-roadmap-staging launcher
color 0A

cd /d "%~dp0"

set "BACKEND_URL=http://127.0.0.1:3012"
set "FRONTEND_URL=http://127.0.0.1:3002"
set "SQLDIR=E:\PostgreSQL\put-roadmap-staging"
set "PSQL="

echo.
echo ===============================================
echo   PUT ROADMAP STAGING - SQL + INSTALL AND RUN
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

if exist "E:\PostgreSQL\18\bin\psql.exe" set "PSQL=E:\PostgreSQL\18\bin\psql.exe"
if not defined PSQL if exist "E:\PostgreSQL\16\bin\psql.exe" set "PSQL=E:\PostgreSQL\16\bin\psql.exe"
if not defined PSQL (
  echo [ERROR] psql.exe not found. Checked:
  echo   E:\PostgreSQL\18\bin\psql.exe
  echo   E:\PostgreSQL\16\bin\psql.exe
  pause
  exit /b 1
)
echo [INFO] psql: %PSQL%
rem База UTF8, консоль Windows по умолчанию WIN1252 — без этого падает на кириллице в SQL.
set "PGCLIENTENCODING=UTF8"
rem Без pager=off psql останавливается на "-- More --" из-за длинного вывода verify.
set "PAGER="
set "PSQL_PAGER="

if not exist "%SQLDIR%\01-schema.sql" (
  echo [ERROR] SQL scripts not found in %SQLDIR%
  pause
  exit /b 1
)
if not exist "%~dp0backend\.env" (
  echo [ERROR] backend\.env not found
  pause
  exit /b 1
)

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
echo [STEP] Reading DATABASE_URL from backend\.env ...
set "PGUSER="
set "PGPASSWORD="
set "PGHOST="
set "PGPORT="
set "PGDATABASE="
for /f "usebackq tokens=1,2,3,4,5 delims=|" %%A in (`
  powershell -NoProfile -Command ^
    "$p='%~dp0backend\.env'; $url=$null;" ^
    "Get-Content -LiteralPath $p | ForEach-Object { if ($_ -match '^\s*DATABASE_URL=(.+)$') { $url=$Matches[1].Trim() } };" ^
    "if (-not $url) { throw 'DATABASE_URL is empty or commented in backend/.env' };" ^
    "if ($url -notmatch '^postgres(?:ql)?://([^:]+):([^@]+)@([^:/]+):?(\d*)/([^/?]+)') { throw 'Cannot parse DATABASE_URL' };" ^
    "$pass=[uri]::UnescapeDataString($Matches[2]);" ^
    "$port=$Matches[4]; if (-not $port) { $port='5432' };" ^
    "Write-Output ($Matches[1] + '|' + $pass + '|' + $Matches[3] + '|' + $port + '|' + $Matches[5])"
`) do (
  set "PGUSER=%%A"
  set "PGPASSWORD=%%B"
  set "PGHOST=%%C"
  set "PGPORT=%%D"
  set "PGDATABASE=%%E"
)
if not defined PGDATABASE (
  echo [ERROR] Failed to parse DATABASE_URL from backend\.env
  echo Uncomment DB_DIALECT=postgres and DATABASE_URL.
  pause
  exit /b 1
)
echo [INFO] Postgres: %PGUSER%@%PGHOST%:%PGPORT%/%PGDATABASE%

echo.
echo [STEP] SQL 01-schema.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\01-schema.sql"
if errorlevel 1 (
  echo [ERROR] 01-schema.sql failed
  pause
  exit /b 1
)

echo [STEP] SQL 04-read-write.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\04-read-write.sql"
if errorlevel 1 (
  echo [ERROR] 04-read-write.sql failed
  pause
  exit /b 1
)

echo [STEP] SQL 05-task-mutations.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\05-task-mutations.sql"
if errorlevel 1 (
  echo [ERROR] 05-task-mutations.sql failed
  pause
  exit /b 1
)

echo [STEP] SQL 06-blocks-stage-deps.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\06-blocks-stage-deps.sql"
if errorlevel 1 (
  echo [ERROR] 06-blocks-stage-deps.sql failed
  pause
  exit /b 1
)

echo [STEP] SQL 07-constraints.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\07-constraints.sql"
if errorlevel 1 (
  echo [ERROR] 07-constraints.sql failed
  pause
  exit /b 1
)

echo [STEP] SQL 08-task-files.sql
"%PSQL%" -X -P pager=off -h %PGHOST% -p %PGPORT% -U %PGUSER% -d %PGDATABASE% -v ON_ERROR_STOP=1 -f "%SQLDIR%\08-task-files.sql"
if errorlevel 1 (
  echo [ERROR] 08-task-files.sql failed
  pause
  exit /b 1
)

echo [INFO] Skip SQL 02-migrate-json.sql / 03-verify.sql: tables are source of truth, stale JSON must not reload them.

echo.
echo [STEP] Starting backend...
start "put-roadmap backend" /D "%~dp0backend" cmd /k "title put-roadmap backend && echo Backend URL: %BACKEND_URL% && npm run dev"

timeout /t 2 /nobreak >nul

echo [STEP] Starting frontend...
start "put-roadmap frontend" /D "%~dp0frontend" cmd /k "title put-roadmap frontend && echo Frontend URL: %FRONTEND_URL% && npm run dev -- --port 3002 --host 127.0.0.1 --strictPort"

echo.
echo [OK] Started.
echo SQL      : %SQLDIR%
echo Frontend : %FRONTEND_URL%
echo Backend  : %BACKEND_URL%
echo Database : %PGDATABASE% @ %PGHOST%:%PGPORT%
echo.
echo If something fails, check opened backend/frontend windows.
echo.
pause
