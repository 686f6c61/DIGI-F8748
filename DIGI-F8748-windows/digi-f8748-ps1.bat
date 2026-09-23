@echo off
rem DIGI F8748 Admin Recovery - lanzador de la version PowerShell (sin Python)
rem Uso SOLO en un router del que seas propietario o tengas permiso explicito.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0digi-f8748.ps1" %*
if errorlevel 1 pause
