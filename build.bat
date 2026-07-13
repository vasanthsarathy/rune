@echo off
if not exist build mkdir build
odin build rune -out:build\rune.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Launching Rune ...
build\rune.exe
