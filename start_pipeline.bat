@echo off
chcp 65001 >nul
title AI FLAC Metadata Pipeline

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

powershell -NoProfile -ExecutionPolicy Bypass -File ".\run_album.ps1"

echo.
echo ========================================
echo Pipeline finished.
echo Please check the _debug_json folder.
echo ========================================
echo.

pause
