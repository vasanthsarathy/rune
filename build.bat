@echo off
if not exist build mkdir build
odin build runtime -build-mode:dll -out:build\odessa.dll -debug
if %errorlevel% neq 0 exit /b 1
odin build host -out:build\odessa.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Built build\odessa.dll and build\odessa.exe
