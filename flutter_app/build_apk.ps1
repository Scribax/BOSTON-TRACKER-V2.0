$env:JAVA_HOME = "C:\Users\franc\Desktop\jdk-17.0.2"
$env:ANDROID_HOME = "C:\Users\franc\Desktop\cmdline-tools"
$env:ANDROID_SDK_ROOT = "C:\Users\franc\Desktop\cmdline-tools"
$env:PUB_CACHE = "C:\Users\franc\AppData\Local\Pub\Cache"
$env:PATH = "C:\Users\franc\Desktop\flutter_341\bin;$env:JAVA_HOME\bin;$env:PATH"

flutter build apk --release

Write-Host "`nAPK en: C:\Users\franc\Desktop\BOSTON TRACKER\flutter_app\build\app\outputs\flutter-apk\app-release.apk"
