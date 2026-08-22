@echo off
chcp 65001 >nul
title MASAPP - Delete AI Models & Cleanup
color 0C

echo ======================================================================
echo           MASAPP - UNINSTALL AI MODELS & STORAGE CLEANUP
echo             ระบบถอนการติดตั้งโมเดล AI และคืนพื้นที่ Harddisk
echo ======================================================================
echo.

where ollama >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] ไม่พบโปรแกรม Ollama ในระบบ ไม่จำเป็นต้องลบโมเดล
    pause
    exit /b 0
)

echo รายการโมเดล AI ที่ติดตั้งอยู่ในเครื่องปัจจุบัน:
echo ----------------------------------------------------------------------
ollama list
echo ----------------------------------------------------------------------
echo.

echo ======================================================================
echo                     เลือกรายการที่ต้องการลบ
echo ======================================================================
echo  [1] ลบโมเดล Embedding (nomic-embed-text)
echo  [2] ลบโมเดลทั้งหมดในเครื่อง (ล้างพื้นที่คืน 100%)
echo  [3] ยกเลิก
echo ======================================================================
set /p choice="กรุณาเลือกตัวเลือก (1-3): "

if "%choice%"=="1" goto :remove_embedding
if "%choice%"=="2" goto :remove_all
if "%choice%"=="3" goto :cancel

echo ตัวเลือกไม่ถูกต้อง
pause
exit /b 0

:remove_embedding
echo.
echo [*] กำลังลบโมเดล nomic-embed-text...
ollama rm nomic-embed-text
echo [✓] ลบโมเดล nomic-embed-text เรียบร้อยแล้ว
goto :finish

:remove_all
echo.
set /p confirm="ท่านแน่ใจหรือไม่ว่าต้องการลบโมเดลทั้งหมด? (Y/N): "
if /i not "%confirm%"=="Y" goto :cancel

echo [*] กำลังลบโมเดลทั้งหมดในระบบ...
for /f "skip=1 tokens=1" %%i in ('ollama list') do (
    if not "%%i"=="" (
        echo กำลังลบ %%i...
        ollama rm %%i 2>nul
    )
)
echo [✓] ลบโมเดลทั้งหมดในระบบเรียบร้อยแล้ว
goto :finish

:finish
echo.
echo ----------------------------------------------------------------------
echo สถานะโมเดลคงเหลือในเครื่อง:
ollama list
echo ----------------------------------------------------------------------
echo.
echo [✓] ดำเนินการเสร็จสิ้น คืนพื้นที่จัดเก็บข้อมูลเรียบร้อยแล้วครับ!
echo.
pause
exit /b 0

:cancel
echo.
echo ยกเลิกการทำงาน
pause
exit /b 0
