param(
  [ValidateSet('run', 'build', 'doctor', 'get')]
  [string]$Mode = 'run',

  [string]$FlutterRoot = 'C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\flutter_windows_3.41.9-stable\flutter',
  [string]$JavaHome = 'C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\jdk-17.0.2',
  [string]$AndroidSdkRoot = 'C:\Users\franc\Desktop\Desarrollo\Flutter & Android SDK\cmdline-tools',
  [string]$ProjectRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $FlutterRoot)) {
  throw "No encontré Flutter en: $FlutterRoot"
}

if (Test-Path $JavaHome) {
  $env:JAVA_HOME = $JavaHome
  $env:PATH = "$JavaHome\bin;$env:PATH"
}

if (Test-Path $AndroidSdkRoot) {
  $env:ANDROID_HOME = $AndroidSdkRoot
  $env:ANDROID_SDK_ROOT = $AndroidSdkRoot
}

$env:PATH = "$FlutterRoot\bin;$env:PATH"

Set-Location $ProjectRoot

switch ($Mode) {
  'doctor' {
    & "$FlutterRoot\bin\flutter.bat" doctor -v
  }
  'get' {
    & "$FlutterRoot\bin\flutter.bat" pub get
  }
  'build' {
    & "$FlutterRoot\bin\flutter.bat" clean
    & "$FlutterRoot\bin\flutter.bat" pub get
    & "$FlutterRoot\bin\flutter.bat" build apk --release
  }
  'run' {
    & "$FlutterRoot\bin\flutter.bat" pub get
    & "$FlutterRoot\bin\flutter.bat" run
  }
}
