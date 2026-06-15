@echo off
setlocal enabledelayedexpansion

rem Build the Android APK and copy it to the user's Desktop.
rem Adjust these paths only if the Flutter SDK or JDK moves.
set "FLUTTER_ROOT=C:\Users\franc\Desktop\Desarrollo\FLUTTER\flutter_git"
set "JAVA_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTER\jdk-17.0.2"
set "ANDROID_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTER\cmdline-tools"
set "PROJECT_DIR=%~dp0"
set "APK_SOURCE=%PROJECT_DIR%build\app\outputs\flutter-apk\app-release.apk"
set "APK_TARGET=%USERPROFILE%\Desktop\BostonTracker.apk"

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo No se encontro Flutter en:
  echo %FLUTTER_ROOT%
  pause
  exit /b 1
)

if exist "%JAVA_HOME%\bin" set "PATH=%JAVA_HOME%\bin;%PATH%"
if exist "%FLUTTER_ROOT%\bin" set "PATH=%FLUTTER_ROOT%\bin;%PATH%"
if exist "%ANDROID_HOME%\bin" set "PATH=%ANDROID_HOME%\bin;%PATH%"

pushd "%PROJECT_DIR%"

echo Cleaning...
call "%FLUTTER_ROOT%\bin\flutter.bat" clean
if errorlevel 1 goto build_failed

echo Getting dependencies...
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
if errorlevel 1 goto build_failed

echo Building APK...
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release
if errorlevel 1 goto build_failed

if not exist "%APK_SOURCE%" (
  echo No se encontro la APK generada:
  echo %APK_SOURCE%
  goto end_failed
)

copy /Y "%APK_SOURCE%" "%APK_TARGET%"
if errorlevel 1 goto end_failed

echo.
echo APK copiada a:
echo %APK_TARGET%
goto end_ok

:build_failed
echo.
echo La compilacion fallo.
goto end_failed

:end_ok
popd
echo Done!
pause
exit /b 0

:end_failed
popd
pause
exit /b 1
