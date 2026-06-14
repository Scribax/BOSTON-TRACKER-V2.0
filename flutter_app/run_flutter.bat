@echo off
setlocal

rem Usage:
rem   run_flutter.bat doctor
rem   run_flutter.bat get
rem   run_flutter.bat build
rem   run_flutter.bat run
rem   run_flutter.bat run <device_id>

set "MODE=%~1"
if "%MODE%"=="" set "MODE=run"
set "TARGET=%~2"

rem Adjust only if your local folders move
set "FLUTTER_ROOT=C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\flutter_windows_3.41.9-stable\flutter"
set "JAVA_HOME=C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\jdk-17.0.2"
set "ANDROID_HOME=C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\cmdline-tools"

rem Convert to 8.3 short paths to avoid issues with spaces and '&'
for %%I in ("%FLUTTER_ROOT%") do set "FLUTTER_ROOT=%%~sI"
for %%I in ("%JAVA_HOME%") do set "JAVA_HOME=%%~sI"
for %%I in ("%ANDROID_HOME%") do set "ANDROID_HOME=%%~sI"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo No se encontro Flutter en:
  echo %FLUTTER_ROOT%
  pause
  exit /b 1
)

if exist "%JAVA_HOME%\bin" set "PATH=%JAVA_HOME%\bin;%PATH%"
if exist "%FLUTTER_ROOT%\bin" set "PATH=%FLUTTER_ROOT%\bin;%PATH%"

set "FLUTTER_WEB_AUTO_DETECT=false"

pushd "%~dp0"

if /I "%MODE%"=="doctor" goto doctor
if /I "%MODE%"=="get" goto get
if /I "%MODE%"=="build" goto build
if /I "%MODE%"=="run" goto run

echo Modo invalido: %MODE%
echo Usar: doctor, get, build, run
goto end

:doctor
call "%FLUTTER_ROOT%\bin\flutter.bat" doctor -v
goto end

:get
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
goto end

:build
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release
goto end

:run
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
if "%TARGET%"=="" (
  call "%FLUTTER_ROOT%\bin\flutter.bat" devices
  echo.
  echo Si queres instalarla en el celular, volve a correr:
  echo   run_flutter.bat run ^<device_id^>
  echo Ejemplo:
  echo   run_flutter.bat run emulator-5554
  goto end
)
call "%FLUTTER_ROOT%\bin\flutter.bat" run -d %TARGET%
goto end

:end
popd
pause
