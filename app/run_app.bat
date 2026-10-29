@echo off
REM ==========================================================================================
REM  ENSA Chad 2018-2025 - Harmonisation explorer (R Shiny)
REM  Double-click this file: the application opens in your web browser.
REM  Keep this window open while using the app; close it to stop the application.
REM ==========================================================================================
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title ENSA Chad harmonisation explorer

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

REM --- Check the app data (prepared before sharing, aggregates only) ---
if not exist "data\ENSA_Chad_crosswalk_2018-2025.xlsx" goto nodata
if not exist "data\indicators_by_round.csv" goto nodata

REM --- Packages (missing ones are installed automatically on first run) ---
"%RSCRIPT%" install_packages.R
if errorlevel 1 (
    echo.
    echo FAILED to install the R packages. See Troubleshooting in README_FIRST.txt
    pause
    exit /b 1
)

REM --- Launch ---
echo.
echo Opening the application in your browser...
echo Close this window to stop the application.
echo.
"%RSCRIPT%" -e "shiny::runApp('.', launch.browser = TRUE)"
pause
exit /b 0

:nodata
echo.
echo The "data" folder of the application is missing or incomplete.
echo Ask the sender for the complete application folder (including "data").
pause
exit /b 1
