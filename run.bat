@echo off
call "%~dp0build.bat"
if %errorlevel% neq 0 exit /b 1
build\odessa.exe
