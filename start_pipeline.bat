@echo off
chcp 65001 >nul
title AI FLAC Metadata Pipeline

:: Force Python to use UTF-8 for all I/O and path handling
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1

echo ========================================
echo AI FLAC Metadata Pipeline
echo ========================================
echo.
cd /d "%~dp0"
echo Current folder:
cd
echo.
echo Starting PowerShell pipeline...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_album.ps1"
echo.
echo ========================================
echo Pipeline finished.
echo Please check the scripts\_debug_album folder.
echo ========================================
echo.
pause