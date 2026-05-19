@echo off
set JAVA_HOME=C:\Users\franc\OneDrive\Escritorio\jdk-17.0.2
set ANDROID_HOME=C:\Users\franc\OneDrive\Escritorio\cmdline-tools
set PATH=%PATH%;C:\Users\franc\OneDrive\Escritorio\flutter_windows_3.41.9-stable\flutter\bin;C:\Users\franc\OneDrive\Escritorio\jdk-17.0.2\bin;C:\Users\franc\OneDrive\Escritorio\cmdline-tools\bin

cd "C:\Users\franc\OneDrive\Escritorio\Proyectos de Software\BostonTracker-main\flutter_app"
flutter clean
flutter pub get
flutter build apk --release
echo Build complete!
pause
