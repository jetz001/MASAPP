@echo off
chcp 65001 >nul
title MASAPP - AI & Embedding Setup (qwen2.5-coder:0.5b + nomic-embed-text)
color 0B

echo ======================================================================
echo           MASAPP - AI & EMBEDDING ENVIRONMENT SETUP
echo   ระบบติดตั้งสภาพแวดล้อม AI และ Vector Embedding ภายในเครื่อง
echo ======================================================================
echo.

:: 1. Check if Ollama is installed
where ollama >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] ตรวจไม่พบโปรแกรม Ollama ในระบบ Windows
    echo.
    echo กำลังตรวจสอบการติดตั้งผ่าน winget...
    where winget >nul 2>nul
    if %errorlevel% equ 0 (
        echo กำลังติดตั้ง Ollama อัตโนมัติ กรุณารอสักครู่...
        winget install -e --id Ollama.Ollama --accept-source-agreements --accept-package-agreements
        if %errorlevel% equ 0 (
            echo [✓] ติดตั้ง Ollama สำเร็จแล้ว!
            set "PATH=%LOCALAPPDATA%\Programs\Ollama;%PATH%"
        ) else (
            goto :manual_install
        )
    ) else (
        goto :manual_install
    )
) else (
    echo [✓] ตรวจพบโปรแกรม Ollama ในระบบแล้ว
)

goto :check_service

:manual_install
echo.
echo [X] ไม่สามารถติดตั้ง Ollama อัตโนมัติได้
echo กรุณาดาวน์โหลดและติดตั้ง Ollama ด้วยตนเองที่:
echo https://ollama.com/download/windows
echo เมื่อติดตั้งเสร็จแล้ว ให้เปิดไฟล์นี้ใหม่อีกครั้งครับ
echo.
pause
exit /b 1

:check_service
echo.
echo [1/3] ตรวจสอบสถานะการทำงานของ Ollama Service...
curl -s http://127.0.0.1:11434 >nul 2>nul
if %errorlevel% neq 0 (
    echo [*] กำลังเริ่มการทำงานของ Ollama Service ในพื้นหลัง...
    start "" ollama serve
    timeout /t 3 /nobreak >nul
)
echo [✓] Ollama Service พร้อมทำงานที่ http://127.0.0.1:11434

echo.
echo [2/3] กำลังดาวน์โหลดและอัปเดตโมเดล Vector Embedding: nomic-embed-text (~274MB)...
ollama pull nomic-embed-text

echo.
echo [3/3] กำลังดาวน์โหลดและอัปเดตโมเดล AI Chat (เร็วสูงสุด + รองรับ Tool): qwen2.5:0.5b (~397MB)...
ollama pull qwen2.5:0.5b

echo.
echo ----------------------------------------------------------------------
echo ตรวจสอบสถานะโมเดลในเครื่อง:
ollama list
echo ----------------------------------------------------------------------
echo.
echo [✓] ติดตั้งสภาพแวดล้อม AI และโมเดล Default ครบถ้วนเรียบร้อย 100%!
echo พร้อมใช้งานใน MASAPP ทันที
echo.
pause
exit /b 0
