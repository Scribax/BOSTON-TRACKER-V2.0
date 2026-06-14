@echo off
:: Build script that works around spaces in Flutter path
set "FLUTTER_ROOT=C:\Users\franc\Desktop\Flutter & Android SDK\flutter_git"
set "JAVA_HOME=C:\Users\franc\Desktop\Flutter & Android SDK\jdk-17.0.2"
set "ANDROID_HOME=C:\Users\franc\Desktop\Flutter & Android SDK\cmdline-tools"

:: Add to PATH using short names to avoid space issues
for %%I in ("%FLUTTER_ROOT%\bin") do set "PATH=%%~sI;%PATH%"
for %%I in ("%JAVA_HOME%\bin") do set "PATH=%%~sI;%PATH%"
for %%I in ("%ANDROID_HOME%\bin") do set "PATH=%%~sI;%PATH%"

cd /d "%~dp0"

echo Cleaning...
call "%FLUTTER_ROOT%\bin\flutter.bat" clean

echo Getting dependencies...
call "%FLUTTER_ROOT%\bin\flutter.bat" pub get

echo Building APK...
call "%FLUTTER_ROOT%\bin\flutter.bat" build apk --release

echo Done!
pause
