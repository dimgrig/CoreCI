@echo off
REM CoreCI/scripts/build-win.bat — сборка Core-based проекта на Windows-хосте.
REM
REM Запуск из корня проекта:
REM   .ci\scripts\build-win.bat
REM   .ci\scripts\build-win.bat --smoke
REM   .ci\scripts\build-win.bat --version 1.1.0 --qt "C:\Qt\5.15.2\mingw81_32"
REM   .ci\scripts\build-win.bat --build-type Debug --clean
REM
REM При отсутствии Core SDK в %LOCALAPPDATA%\Core\<ver>\ соберёт его
REM через build-core-win.bat (рядом с этим скриптом).

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"

set "VERSION=1.1.0"
set "QT_DIR=C:\Qt\5.15.2\mingw81_32"
set "BUILD_TYPE=Release"
set "BUILD_DIR=build"
set "DO_CLEAN=0"
set "DO_SMOKE=0"
set "APP_NAME="

:parse_args
if "%~1"=="" goto after_args
if /i "%~1"=="--clean"      (set "DO_CLEAN=1"     & shift & goto parse_args)
if /i "%~1"=="--smoke"      (set "DO_SMOKE=1"     & shift & goto parse_args)
if /i "%~1"=="--version"    (set "VERSION=%~2"    & shift & shift & goto parse_args)
if /i "%~1"=="--qt"         (set "QT_DIR=%~2"     & shift & shift & goto parse_args)
if /i "%~1"=="--build-type" (set "BUILD_TYPE=%~2" & shift & shift & goto parse_args)
if /i "%~1"=="--name"       (set "APP_NAME=%~2"   & shift & shift & goto parse_args)
if /i "%~1"=="-h"           goto print_help
if /i "%~1"=="--help"       goto print_help
echo Unknown argument: %~1 & exit /b 1

:print_help
echo Usage: .ci\scripts\build-win.bat [options]
echo   --clean --smoke --version X.Y.Z --qt PATH --build-type Release^|Debug --name APP
exit /b 0

:after_args
REM Скрипт лежит в <project>\.ci\scripts\ — корень проекта двумя уровнями выше.
pushd "%SCRIPT_DIR%..\.." || (echo ERROR: pushd failed & exit /b 1)

if not exist "CMakeLists.txt" (
    echo ERROR: CMakeLists.txt not found in %CD%
    popd & exit /b 1
)

REM ── Auto-detect APP_NAME (для smoke-пути; --name переопределяет) ──
if not defined APP_NAME (
    for %%f in (*.pro) do (
        if not defined APP_NAME set "APP_NAME=%%~nf"
    )
)
if not defined APP_NAME (
    echo WARNING: no .pro in %CD% and --name not given; smoke may fail
    set "APP_NAME=app"
)

echo == %APP_NAME% Windows build ==
echo   source    : %CD%
echo   Qt        : %QT_DIR%
echo   version   : %VERSION%
echo   build type: %BUILD_TYPE%
echo.

if not exist "%QT_DIR%\bin\qmake.exe" (
    echo ERROR: Qt not found at %QT_DIR%
    popd & exit /b 1
)

REM ── Найти Qt-mingw, нормализовать, forward-slash ─────
set "QT_MINGW_BIN="
for %%P in (
    "%QT_DIR%\..\..\Tools\mingw810_32\bin"
    "%QT_DIR%\..\Tools\mingw810_32\bin"
    "C:\Qt\Tools\mingw810_32\bin"
) do (
    if not defined QT_MINGW_BIN if exist "%%~P\g++.exe" (
        for %%I in ("%%~P") do set "QT_MINGW_BIN=%%~fI"
    )
)
if not defined QT_MINGW_BIN (
    echo ERROR: Qt mingw ^(g++.exe^) not found. Tried:
    echo   %QT_DIR%\..\..\Tools\mingw810_32\bin
    echo   %QT_DIR%\..\Tools\mingw810_32\bin
    echo   C:\Qt\Tools\mingw810_32\bin
    echo        Override: set QT_MINGW_BIN=path\to\mingw\bin
    popd & exit /b 1
)
set "QT_MINGW_BIN_CMAKE=%QT_MINGW_BIN:\=/%"
set "PATH=%QT_MINGW_BIN%;%PATH%"
echo Using mingw: %QT_MINGW_BIN%

REM ── Core SDK ──────────────────────────────────────────────
set "CORE_SDK_ROOT=%LOCALAPPDATA%\Core\%VERSION%"
if exist "%CORE_SDK_ROOT%\lib\cmake\Core\CoreConfig.cmake" (
    echo === Core SDK found: %CORE_SDK_ROOT% ===
) else (
    echo === Core SDK not found, building natively ===
    call "%SCRIPT_DIR%build-core-win.bat" %VERSION% "%QT_DIR%" "%CORE_SDK_ROOT%"
    if errorlevel 1 (
        echo ERROR: failed to build Core SDK
        popd & exit /b 1
    )
)

REM ── Clean ─────────────────────────────────────────────────
if "%DO_CLEAN%"=="1" (
    if exist "%BUILD_DIR%" (
        echo === rm -rf %BUILD_DIR% ===
        rmdir /s /q "%BUILD_DIR%"
    )
)

REM ── Configure ─────────────────────────────────────────────
echo === Configure ===
cmake -B "%BUILD_DIR%" -G "MinGW Makefiles" ^
    -DCMAKE_PREFIX_PATH="%QT_DIR%;%CORE_SDK_ROOT%" ^
    -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
    -DCMAKE_C_COMPILER="%QT_MINGW_BIN_CMAKE%/gcc.exe" ^
    -DCMAKE_CXX_COMPILER="%QT_MINGW_BIN_CMAKE%/g++.exe"
if errorlevel 1 ( popd & exit /b 1 )

REM ── Build ─────────────────────────────────────────────────
echo === Build ===
cmake --build "%BUILD_DIR%" -j
if errorlevel 1 ( popd & exit /b 1 )

REM ── Smoke ─────────────────────────────────────────────────
if "%DO_SMOKE%"=="1" (
    echo === Smoke ===
    set "MODBUS_SMOKE=1"
    "%BUILD_DIR%\%APP_NAME%.exe"
    set "RC=!errorlevel!"
    set "MODBUS_SMOKE="
    if !RC! neq 0 (
        echo ERROR: smoke failed exit=!RC!
        popd & exit /b !RC!
    )
    echo [+] smoke OK
)

echo.
echo == Done ==
echo   exe: %CD%\%BUILD_DIR%\%APP_NAME%.exe
popd
endlocal