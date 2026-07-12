@echo off
if "%~1"=="" (
	echo Usage: build_sketch.bat ^<sketch-name^>
	exit /b 1
)
if not exist build mkdir build
odin build sketches\%~1 -out:build\%~1.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Running %~1 ...
build\%~1.exe
