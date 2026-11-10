@echo off
cd /d "%~dp0"
title Installa DirectSwitch-Free-Install.ipa su iPhone
echo ============================================================================
echo   INSTALLAZIONE RAPIDA DIRECTSWITCH iOS SU iPHONE (SIDELOADLY USB)
echo ============================================================================
echo.
if not exist "%CD%\DirectSwitch-Free-Install.ipa" (
    echo [ATTENZIONE] Il file DirectSwitch-Free-Install.ipa non e' ancora presente in:
    echo   %CD%\DirectSwitch-Free-Install.ipa
    echo.
    echo Esegui prima la compilazione macOS su GitHub Actions ^(workflow directswitch-ci-release.yml^)
    echo per generare automaticamente DirectSwitch-Free-Install.ipa e DirectSwitch-Release.ipa.
    echo.
    pause
    exit /b 1
)

echo   1. Pacchetto App iPhone trovato:
echo      %CD%\DirectSwitch-Free-Install.ipa
echo.
echo Avvio Sideloadly...
if exist "%LOCALAPPDATA%\Sideloadly\sideloadly.exe" (
    start "" "%LOCALAPPDATA%\Sideloadly\sideloadly.exe"
) else if exist "%USERPROFILE%\Downloads\SideloadlySetup64.exe" (
    start "" "%USERPROFILE%\Downloads\SideloadlySetup64.exe"
) else (
    echo [INFO] Apri Sideloadly sul tuo PC ^(https://sideloadly.io^).
)
echo.
echo COME INSTALLARE ADESSO SU iPHONE:
echo   1. Collega l'iPhone al PC con il cavo USB ^(e premi "Autorizza" sullo schermo dell'iPhone^).
echo   2. In Sideloadly trascina il file "DirectSwitch-Free-Install.ipa".
echo   3. Inserisci la tua normale email Apple ID gratuita e clicca su "START".
echo   4. Sull'iPhone vai in Impostazioni ^> Generali ^> Gestione VPN e dispositivi ^> Autorizza profilo.
echo.
pause
