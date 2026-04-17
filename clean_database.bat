@echo off
REM Delete the old corrupted database file to force fresh initialization
REM Location: C:\Users\PCT\OneDrive\เอกสาร\masapp.db

setlocal enabledelayedexpansion

set "DB_PATH=%USERPROFILE%\OneDrive\เอกสาร\masapp.db"

if exist "!DB_PATH!" (
    echo Deleting old database: !DB_PATH!
    del "!DB_PATH!"
    if exist "!DB_PATH!" (
        echo ERROR: Could not delete database file. Make sure it's not in use.
        pause
        exit /b 1
    ) else (
        echo SUCCESS: Database deleted. App will recreate it on next run.
        pause
        exit /b 0
    )
) else (
    echo Database file not found at: !DB_PATH!
    pause
    exit /b 0
)
