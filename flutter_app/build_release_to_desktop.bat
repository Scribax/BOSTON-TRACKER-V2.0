@echo off
setlocal
set "EXIT_CODE=0"

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

call :kill_locks
call :cleanup_build

call "%FLUTTER_ROOT%\bin\flutter.bat" pub get
if errorlevel 1 goto build_failed

call :build_release
if errorlevel 1 (
  echo.
  echo Reintentando release una vez despues de limpiar locks...
  call :kill_locks
  call :cleanup_build
  call :build_release
  if errorlevel 1 goto build_failed
)

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

goto end

:build_release
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release --no-tree-shake-icons
exit /b %ERRORLEVEL%

:cleanup_build
if exist "%CD%\build" rmdir /s /q "%CD%\build"
if exist "%CD%\.dart_tool" rmdir /s /q "%CD%\.dart_tool"
if exist "%CD%\.flutter-plugins-dependencies" del /f /q "%CD%\.flutter-plugins-dependencies"
if exist "%CD%\.flutter-plugins" del /f /q "%CD%\.flutter-plugins"
exit /b 0

:kill_locks
for %%P in (java.exe javaw.exe dart.exe flutter.bat gradle.bat) do (
  taskkill /f /im %%P >nul 2>nul
)
exit /b 0

:build_failed
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo La compilacion release fallo. No se copio ningun APK.

:end
popd
pause
exit /b %EXIT_CODE%
