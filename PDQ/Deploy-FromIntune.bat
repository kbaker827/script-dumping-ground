@echo off
:: PDQ Deploy Launcher for Intune
:: Simple batch wrapper to call PowerShell script
:: This ensures proper exit codes for Intune detection

powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0Invoke-PDQDeployFromIntune.ps1" -PackageName "%%1" -WaitForCompletion

exit /b %ERRORLEVEL%
