@echo off
setlocal

rem Debug runner for the TECNO phone connected on this machine.
set "DEVICE_ID=11459254AB102563"
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

call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
adb start-server

start "Boston Tracker Logs" cmd /k "set PATH=%ANDROID_HOME%\platform-tools;%PATH% && adb logcat -v time | findstr /i /c:""BostonTracker"" /c:""Socket"" /c:""Destination"" /c:""join-delivery"" /c:""deliveryDestination"" /c:""ACK"""

call "%FLUTTER_ROOT%\bin\flutter.bat" run -d %DEVICE_ID%

popd
pause
