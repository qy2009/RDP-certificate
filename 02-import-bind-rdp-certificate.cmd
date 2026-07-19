@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Import a PFX into Local Computer\Personal and bind it to the RDP-Tcp
rem listener. Uses WMIC on Windows 7 and Windows PowerShell as a fallback on
rem newer Windows versions where WMIC may be absent.
rem
rem Run from an elevated Command Prompt:
rem   02-import-bind-rdp-certificate.cmd C:\path\host.example.com.pfx
rem
rem The matching host.example.com.sha1 file produced by script 01 must be in
rem the same directory as the PFX. certutil will securely prompt for the PFX
rem password unless RDP_PFX_PASSWORD is already defined in the environment.

if "%~1"=="" goto :usage

net session >nul 2>&1
if errorlevel 1 (
  echo Error: run this script from a Command Prompt opened with Run as administrator.
  exit /b 1
)

set "PFX_FILE=%~f1"
set "SHA1_FILE=%~dpn1.sha1"

if not exist "!PFX_FILE!" (
  echo Error: PFX file not found: !PFX_FILE!
  exit /b 1
)

if not exist "!SHA1_FILE!" (
  echo Error: matching thumbprint file not found: !SHA1_FILE!
  exit /b 1
)

set "THUMBPRINT="
set /p "THUMBPRINT="<"!SHA1_FILE!"
set "THUMBPRINT=!THUMBPRINT: =!"
set "THUMBPRINT=!THUMBPRINT::=!"

if "!THUMBPRINT!"=="" (
  echo Error: the thumbprint file is empty.
  exit /b 1
)

echo(!THUMBPRINT!| %SystemRoot%\System32\findstr.exe /R /X "[0-9A-Fa-f]*" >nul
if errorlevel 1 (
  echo Error: the thumbprint contains non-hexadecimal characters.
  exit /b 1
)

if "!THUMBPRINT:~39,1!"=="" (
  echo Error: the SHA-1 certificate thumbprint is shorter than 40 characters.
  exit /b 1
)
if not "!THUMBPRINT:~40,1!"=="" (
  echo Error: the SHA-1 certificate thumbprint is longer than 40 characters.
  exit /b 1
)

echo Importing the certificate into Local Computer\Personal ...
if defined RDP_PFX_PASSWORD (
  certutil.exe -f -p "!RDP_PFX_PASSWORD!" -importPFX My "!PFX_FILE!"
) else (
  echo Enter the PFX password when certutil prompts for it.
  certutil.exe -f -importPFX My "!PFX_FILE!"
)
if errorlevel 1 (
  echo Error: certutil could not import the PFX.
  exit /b 1
)

certutil.exe -store My "!THUMBPRINT!" >nul
if errorlevel 1 (
  echo Error: the imported certificate was not found in Local Computer\Personal.
  exit /b 1
)

set "BOUND=0"
where.exe wmic.exe >nul 2>&1
if not errorlevel 1 (
  echo Binding the certificate through the Terminal Services WMI provider ...
  wmic.exe /namespace:\\root\cimv2\TerminalServices path Win32_TSGeneralSetting set SSLCertificateSHA1Hash="!THUMBPRINT!"
  if not errorlevel 1 set "BOUND=1"
)

if "!BOUND!"=="0" (
  where.exe powershell.exe >nul 2>&1
  if errorlevel 1 (
    echo Error: neither WMIC nor Windows PowerShell is available to bind the certificate.
    exit /b 1
  )

  echo WMIC is unavailable or failed; trying Windows PowerShell ...
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-WmiObject -Class 'Win32_TSGeneralSetting' -Namespace 'root\cimv2\TerminalServices' ^| Set-WmiInstance -Arguments @{SSLCertificateSHA1Hash='!THUMBPRINT!'}"
  if errorlevel 1 (
    echo Error: the Terminal Services WMI provider could not bind the certificate.
    exit /b 1
  )
  set "BOUND=1"
)

echo.
echo Certificate imported and bound successfully.
echo Thumbprint: !THUMBPRINT!
echo.
echo Reboot Windows before testing so the RDP listener reloads the certificate.
echo This script intentionally does not restart TermService because doing so can
echo disconnect a remote session and may leave you without remote access.
exit /b 0

:usage
echo Usage: %~nx0 C:\path\rdp-hostname.pfx
echo The matching .sha1 file must be beside the PFX.
exit /b 2
