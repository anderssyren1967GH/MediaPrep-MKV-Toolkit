@echo off
rem Copyright (C) 2026 Anders Syrén
rem SPDX-License-Identifier: GPL-3.0-or-later
cd /d "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0App\MediaPrep-Start.ps1"
exit /b 0
