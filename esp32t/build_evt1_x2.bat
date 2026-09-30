@echo off
setlocal
cd /d "%~dp0"
if not defined GOWIN_SH set "GOWIN_SH=C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe"
"%GOWIN_SH%" build.tcl
if errorlevel 1 exit /b 1
if not exist "build" mkdir build
copy /y "impl\pnr\evt1_x2.fs" "build\evt1_x2.fs" >nul
if errorlevel 1 exit /b 1
copy /y "impl\pnr\evt1_x2.bin" "build\evt1_x2.bin" >nul
if errorlevel 1 exit /b 1
