@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Installa DirectSwitch su Smartphone Android (Permanente)

set "ADB_EXE=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
set "RELEASE_APK=%CD%\DirectSwitch-Android\app\build\outputs\apk\release\app-release.apk"
set "APK_PATH=%CD%\DirectSwitch-Android-Install.apk"
if exist "%RELEASE_APK%" (
    copy /y "%RELEASE_APK%" "%APK_PATH%" >nul 2>&1
)
if not exist "%APK_PATH%" (
    set "APK_PATH=%RELEASE_APK%"
)

echo ============================================================================
echo   INSTALLATORE DIRETTO DIRECTSWITCH PER SMARTPHONE ANDROID
echo ============================================================================
echo.

if not exist "%APK_PATH%" (
    echo [ERRORE] File APK non trovato in: %APK_PATH%
    pause
    exit /b 1
)

if not exist "%ADB_EXE%" (
    echo [AVVISO] ADB non trovato. Copia "%APK_PATH%" sul telefono e toccalo per installarlo!
    pause
    exit /b 0
)

"%ADB_EXE%" start-server >nul 2>&1
"%ADB_EXE%" install -r "%APK_PATH%"
if errorlevel 1 (
    echo.
    echo [INFO] Collega lo smartphone con Debug USB attivo o copia DirectSwitch-Android-Install.apk sul telefono!
    pause
    exit /b 1
)

"%ADB_EXE%" shell am start -n com.directswitch.android/.MainActivity
echo.
echo ============================================================================
echo   DIRECTSWITCH INSTALLATO E AVVIATO CON SUCCESSO!
echo ============================================================================
pause
