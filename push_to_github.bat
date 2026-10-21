@echo off
chcp 65001 >nul
echo ====================================================
echo        ระบบส่งโค้ดขึ้น GitHub เพื่อสร้าง APK อัตโนมัติ
echo ====================================================
echo.

set PATH=C:\Program Files\Git\cmd;%PATH%

echo กรุณาสร้าง New Repository บน GitHub (ตั้งชื่ออะไรก็ได้ เช่น ax_app)
echo จากนั้นคัดลอก HTTPS Repository URL มาวางด้านล่างนี้
echo ตัวอย่างเช่น: https://github.com/your-username/ax_app.git
echo.
set /p REPO_URL="ระบุ GitHub URL ของคุณ: "

if "%REPO_URL%"=="" (
    echo [ผิดพลาด] คุณยังไม่ได้ระบุ GitHub URL
    pause
    exit /b 1
)

echo.
echo กำลังตั้งค่า Remote Origin...
git remote remove origin >nul 2>&1
git remote add origin %REPO_URL%

echo กำลังส่งโค้ดขึ้น GitHub (Branch: main)...
git push -u origin main

if %errorlevel% neq 0 (
    echo.
    echo [แจ้งเตือน] เกิดข้อผิดพลาดในการ Push
    echo กรุณาตรวจสอบว่า URL ถูกต้อง หรือตรวจสอบการล็อกอิน GitHub ของคุณ
    pause
    exit /b %errorlevel%
)

echo.
echo ====================================================
echo [สำเร็จ!] โค้ดถูกส่งขึ้น GitHub เรียบร้อยแล้ว
echo ระบบ GitHub Actions กำลังสร้างไฟล์ APK ให้คุณในระบบคลาวด์
echo คุณสามารถเข้าไปดูสถานะและดาวน์โหลด APK ได้ที่แท็บ 'Actions' บน GitHub
echo ====================================================
echo.
pause
