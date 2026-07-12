@echo off
if not exist build mkdir build
odin build odessa -out:build\odessa.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Launching Odessa ...
build\odessa.exe
