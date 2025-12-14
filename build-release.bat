@echo off
setlocal enabledelayedexpansion

REM Get version from pubspec.yaml
for /f "tokens=2" %%i in ('findstr "^version:" pubspec.yaml') do set VERSION_FULL=%%i
for /f "tokens=1 delims=+" %%i in ("%VERSION_FULL%") do set VERSION=%%i
for /f "tokens=2 delims=+" %%i in ("%VERSION_FULL%") do set BUILD_NUMBER=%%i

if "%VERSION%"=="" (
    echo Version not found in pubspec.yaml. Exiting...
    exit /b 1
)
if "%BUILD_NUMBER%"=="" (
    echo Build number not found in pubspec.yaml. Exiting...
    exit /b 1
)

echo Found version: %VERSION%
echo Found build number: %BUILD_NUMBER%

REM Build release APKs
echo Building universal APK...
call flutter build apk --build-number=%BUILD_NUMBER% --build-name=%VERSION% --release
if errorlevel 1 (
    echo Failed to build universal APK
    pause
    exit /b 1
)

echo Building ABI-specific APKs...
call flutter build apk --split-per-abi --build-number=%BUILD_NUMBER% --build-name=%VERSION% --release
if errorlevel 1 (
    echo Failed to build ABI-specific APKs
    pause
    exit /b 1
)

REM Change to output directory
cd build\app\outputs\flutter-apk

REM Function to rename files (using labels as functions)
call :rename_apk "arm64-v8a"
call :rename_apk "armeabi-v7a"
call :rename_apk "x86_64"

REM Handle the universal APK (if any)
if exist app-release.apk (
    ren app-release.apk boorusphere-%VERSION%-universal.apk
    if exist app-release.apk.sha1 ren app-release.apk.sha1 boorusphere-%VERSION%-universal.apk.sha1
    echo Renamed app-release.apk to boorusphere-%VERSION%-universal.apk
) else (
    echo File app-release.apk not found. Skipping...
)

echo Build complete!
pause
goto :eof

:rename_apk
set ARCH=%~1
if exist app-%ARCH%-release.apk (
    ren app-%ARCH%-release.apk boorusphere-%VERSION%-%ARCH%.apk
    if exist app-%ARCH%-release.apk.sha1 ren app-%ARCH%-release.apk.sha1 boorusphere-%VERSION%-%ARCH%.apk.sha1
    echo Renamed app-%ARCH%-release.apk to boorusphere-%VERSION%-%ARCH%.apk
) else (
    echo File app-%ARCH%-release.apk not found. Skipping...
)
goto :eof
