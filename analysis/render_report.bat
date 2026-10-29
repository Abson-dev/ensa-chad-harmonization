@echo off
REM ==========================================================================================
REM  ENSA Chad 2018-2025 - Analysis by domain (Word report)
REM  Double-click this file: the report is rebuilt from the harmonised data and opened in Word.
REM ==========================================================================================
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title ENSA Chad analysis report

REM --- Find R ---
set "RSCRIPT="
for /f "delims=" %%R in ('where Rscript 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%R"
if not defined RSCRIPT (
    for /d %%D in ("%ProgramFiles%\R\R-*" "%LOCALAPPDATA%\Programs\R\R-*") do (
        if exist "%%~D\bin\Rscript.exe" set "RSCRIPT=%%~D\bin\Rscript.exe"
    )
)
if not defined RSCRIPT (
    echo.
    echo R was not found on this computer.
    echo Install R from https://cran.r-project.org/bin/windows/base/ and run this file again.
    pause
    exit /b 1
)

REM --- The harmonised data must exist (python run_harmonize.py in the parent folder) ---
if not exist "..\output\ensa_core.csv" (
    echo.
    echo Harmonised data not found in ..\output
    echo Run the pipeline first: python run_harmonize.py  (see ..\SETUP.md^)
    pause
    exit /b 1
)

echo.
echo Building the report (about 1-2 minutes)...
echo.
"%RSCRIPT%" render_report.R
if errorlevel 1 (
    echo.
    echo FAILED to build the report. See the messages above.
    pause
    exit /b 1
)
start "" "output\ENSA_Chad_analysis_by_domain.docx"
exit /b 0
