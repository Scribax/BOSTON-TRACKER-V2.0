@echo off
setlocal

rem Dedicated runner for the TECNO phone detected on this machine.
set "DEVICE_ID=11459254AB102563"

rem Adjust only if your local folders move
set "FLUTTER_ROOT=C:\Users\franc\Desktop\Desarrollo\FLUTTE~1\FLUTTE~1.9-S\flutter"
set "JAVA_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTE~1\JDK-17~1.2"
set "ANDROID_HOME=C:\Users\franc\Desktop\Desarrollo\FLUTTE~1\cmdline-tools"
set "PLATFORM_TOOLS=%ANDROID_HOME%\platform-tools"

rem Convert to 8.3 short paths to avoid issues with spaces and '&'
for %%I in ("%FLUTTER_ROOT%") do set "FLUTTER_ROOT=%%~sI"
for %%I in ("%JAVA_HOME%") do set "JAVA_HOME=%%~sI"
for %%I in ("%ANDROID_HOME%") do set "ANDROID_HOME=%%~sI"
for %%I in ("%PLATFORM_TOOLS%") do set "PLATFORM_TOOLS=%%~sI"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
set "ANDROID_HOME=%ANDROID_SDK_ROOT%"
set "PUB_CACHE=%USERPROFILE%\AppData\Local\Pub\Cache"
set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

if not exist "%FLUTTER_ROOT%\bin\flutter.bat" (
  echo No se encontro Flutter en:
  echo %FLUTTER_ROOT%
  pause
  exit /b 1
)

if exist "%JAVA_HOME%\bin" set "PATH=%JAVA_HOME%\bin;%PATH%"
if exist "%PLATFORM_TOOLS%" set "PATH=%PLATFORM_TOOLS%;%PATH%"
if exist "%FLUTTER_ROOT%\bin" set "PATH=%FLUTTER_ROOT%\bin;%PATH%"

pushd "%~dp0"

if exist "android\.gradle" rmdir /s /q "android\.gradle"
if exist "android\.kotlin" rmdir /s /q "android\.kotlin"
if exist "android\build" rmdir /s /q "android\build"
if exist "build" rmdir /s /q "build"

call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
adb start-server
call "%FLUTTER_ROOT%\bin\flutter.bat" run -d %DEVICE_ID%

popd
pause
