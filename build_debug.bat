@echo off
setlocal enabledelayedexpansion

REM Build script for Odin projects with RAD Debugger
REM Usage: build_debug.bat <project_directory> [--launch-debugger]

set "PROJECT_DIR=%~1"
set "LAUNCH_DEBUGGER=%~2"

REM Extract just the directory name from the full path
for %%I in ("%PROJECT_DIR%") do set "PROJECT_NAME=%%~nxI"

REM Validate we're in an Odin project directory
if not exist "%PROJECT_DIR%\*.odin" (
    echo Error: No .odin files found in %PROJECT_DIR%
    exit /b 1
)

REM Navigate to project directory
cd /d "%PROJECT_DIR%"

REM Create build directory if it doesn't exist
if not exist "build" mkdir build

REM Build with debug symbols
echo Building %PROJECT_NAME% with debug symbols...
odin build . -debug -o:none -out:build\%PROJECT_NAME%.exe -pdb-name:build\%PROJECT_NAME%.pdb

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b 1
)

echo Build successful: build\%PROJECT_NAME%.exe

REM Launch debugger if requested
if "%LAUNCH_DEBUGGER%"=="--launch-debugger" (
    echo Launching RAD Debugger...
    raddbg build\%PROJECT_NAME%.exe
)

exit /b 0
