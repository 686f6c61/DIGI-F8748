@echo off
setlocal
cd /d "%~dp0"

REM ============================================================
REM  DIGI F8748 Admin Recovery CLI - launcher para Windows
REM  Uso SOLO en un router del que seas propietario o tengas
REM  permiso explicito para gestionar.
REM ============================================================

where py >nul 2>nul
if errorlevel 1 (
    echo [x] Python no encontrado.
    echo     Instala Python 3.10 o superior desde https://www.python.org/downloads/
    echo     IMPORTANTE: marca "Add python.exe to PATH" al instalar.
    pause
    exit /b 1
)

if not exist .venv (
    echo [*] Primera ejecucion: preparando entorno...
    py -3 -m venv .venv
    if errorlevel 1 ( echo [x] No se pudo crear el entorno virtual. & pause & exit /b 1 )
    ".venv\Scripts\python" -m pip install --quiet --upgrade pip
    ".venv\Scripts\pip" install --quiet -r requirements.txt
    if errorlevel 1 ( echo [x] Fallo instalando dependencias. Revisa tu conexion. & pause & exit /b 1 )
    echo [+] Entorno listo.
)

".venv\Scripts\python" digi-f8748.py %*
if errorlevel 1 pause
endlocal
