@echo off
REM ============================================================
REM Build and Run AuraStudio.App desde dentro de la VM Windows
REM Uso: doble-clic o ".\BuildAndRun.bat" en Developer PowerShell
REM ============================================================

set PROJECT_ROOT=%~dp0..
set SLN_FILE=%PROJECT_ROOT%\AuraStudio.Windows.slnx

echo 🔨 Building Aura Studio...
dotnet build "%SLN_FILE%" -c Debug -v minimal

if errorlevel 1 (
    echo ❌ Build failed
    pause
    exit /b 1
)

echo ✅ Build successful
echo.

echo 🚀 Launching Visual Studio 2022...
set VS_PATH="%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
if not exist %VS_PATH% (
    set VS_PATH="%ProgramFiles%\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe"
)

start "" %VS_PATH% "%SLN_FILE%"

echo.
echo ✅ Visual Studio opened. In VS:
echo    1. Right-click AuraStudio.App → Set as Startup Project
echo    2. Platform: x64 (top toolbar)
echo    3. Press F5 to debug
echo.
pause