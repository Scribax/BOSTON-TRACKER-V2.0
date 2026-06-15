@echo off
setlocal

set "FLUTTER_ROOT=C:\Users\franc\Desktop\Desarrollo\FLUTTER\flutter_git"
set "JAVA_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTER\jdk-17.0.2"
set "ANDROID_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTER\cmdline-tools"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "PUB_CACHE=D:\FlutterCache\Pub"
set "GRADLE_USER_HOME=D:\FlutterCache\Gradle"

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo No se encontro Flutter en:
  echo %FLUTTER_ROOT%
  pause
  exit /b 1
)

if exist "%JAVA_HOME%\bin" set "PATH=%JAVA_HOME%\bin;%PATH%"
if exist "%ANDROID_HOME%\platform-tools" set "PATH=%ANDROID_HOME%\platform-tools;%PATH%"
if exist "%FLUTTER_ROOT%\bin" set "PATH=%FLUTTER_ROOT%\bin;%PATH%"

pushd "%~dp0"

call "%FLUTTER_ROOT%\bin\flutter.bat" clean
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release

set "APK_SRC=%CD%\build\app\outputs\flutter-apk\app-release.apk"
for /f "delims=" %%D in ('powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"') do set "DESKTOP=%%D"

if not exist "%APK_SRC%" (
  echo No se encontro el APK generado en:
  echo %APK_SRC%
  popd
  pause
  exit /b 1
)

copy /Y "%APK_SRC%" "%DESKTOP%\boston-tracker-release.apk" >nul

echo APK copiado a:
echo %DESKTOP%\boston-tracker-release.apk

popd
pause
