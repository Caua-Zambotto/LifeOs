@echo off
rem Abre o LifeOS no Windows: inicia o servidor local e abre uma janela de app no Edge.
cd /d "%~dp0"
start "LifeOS - servidor" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor.ps1"
timeout /t 2 /nobreak >nul
start "" msedge --app=http://localhost:8765/ 2>nul || start "" http://localhost:8765/
