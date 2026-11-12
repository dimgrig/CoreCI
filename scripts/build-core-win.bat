@echo off
setlocal enabledelayedexpansion

set "VERSION=%~1"
set "QT_DIR=%~2"
set "INSTALL_DIR=%~3"

if "%VERSION%"==""     set "VERSION=1.1.0"
if "%QT_DIR%"==""      set "QT_DIR=C:\Qt\5.15.2\mingw81_32"
if "%INSTALL_DIR%"=="" set "INSTALL_DIR=%LOCALAPPDATA%\Core\%VERSION%"

echo === Core SDK native build ===
echo   version : %VERSION%
echo   Qt      : %QT_DIR%
echo   install : %INSTALL_DIR%
echo.

if not exist "%QT_DIR%\bin\qmake.exe" (
    echo ERROR: Qt not found at %QT_DIR%
    exit /b 1
)

REM ── Найти Qt-mingw, нормализовать, forward-slash ──────────
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
    echo ERROR: Qt mingw ^(g++.exe^) not found at any of:
    echo   %QT_DIR%\..\..\Tools\mingw810_32\bin
    echo   C:\Qt\Tools\mingw810_32\bin
    exit /b 1
)
set "QT_MINGW_BIN_CMAKE=%QT_MINGW_BIN:\=/%"
set "PATH=%QT_MINGW_BIN%;%PATH%"
echo Using mingw: %QT_MINGW_BIN%
"%QT_MINGW_BIN%\g++.exe" --version | findstr /C:"g++"
echo.

set "CORE_TMP=%TEMP%\Core-%VERSION%-native"
if exist "%CORE_TMP%" rmdir /s /q "%CORE_TMP%"

echo === Cloning Core v%VERSION% ===
git clone --branch v%VERSION% --depth 1 https://github.com/dimgrig/Core.git "%CORE_TMP%"
if errorlevel 1 exit /b 1

echo === Building ===
pushd "%CORE_TMP%"
cmake -B build -G "MinGW Makefiles" ^
    -DCMAKE_PREFIX_PATH="%QT_DIR%" ^
    -DCMAKE_INSTALL_PREFIX="%INSTALL_DIR%" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DBUILD_TESTING=OFF ^
    -DCMAKE_C_COMPILER="%QT_MINGW_BIN_CMAKE%/gcc.exe" ^
    -DCMAKE_CXX_COMPILER="%QT_MINGW_BIN_CMAKE%/g++.exe"
if errorlevel 1 ( popd & exit /b 1 )
cmake --build build -j
if errorlevel 1 ( popd & exit /b 1 )
cmake --install build
if errorlevel 1 ( popd & exit /b 1 )
popd

echo.
echo === Done ===
echo Core SDK %VERSION% installed at: %INSTALL_DIR%
endlocal
