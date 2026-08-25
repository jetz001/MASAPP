@echo off
echo ===================================================
echo   MASAPP - Production Release ^& Installer Build
echo ===================================================
echo.

echo [1/5] Fetching Flutter dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] flutter pub get failed.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [2/5] Generating Windows Icons ^& Assets...
call dart run flutter_launcher_icons
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] flutter_launcher_icons had a warning, continuing...
)

echo.
echo [3/5] Building Flutter Windows Release executable...
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter Windows build failed!
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo [4/5] Checking Inno Setup Compiler (ISCC)...
set ISCC_PATH="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist %ISCC_PATH% (
    set ISCC_PATH="C:\Program Files\Inno Setup 6\ISCC.exe"
)
if not exist %ISCC_PATH% (
    set ISCC_PATH="%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
)

if exist %ISCC_PATH% (
    echo [5/5] Compiling MASAPP Installer (.exe)...
    %ISCC_PATH% masapp_installer.iss
    if %ERRORLEVEL% EQU 0 (
        echo.
        echo ===================================================
        echo   BUILD ^& INSTALLER COMPLETED SUCCESSFULLY!
        echo   Output folder: Output\
        echo ===================================================
    ) else (
        echo [ERROR] Inno Setup compilation failed.
    )
) else (
    echo [NOTE] Inno Setup (ISCC.exe) not found in default paths.
    echo Release binaries are available in:
    echo build\windows\x64\runner\Release\
)

echo.
pause
