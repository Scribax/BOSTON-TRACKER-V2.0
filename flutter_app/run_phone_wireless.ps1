param(
  [string]$DeviceId = "",
  [string]$FlutterRoot = "C:\Users\franc\Desktop\Desarrollo\FLUTTER\flutter_git"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Write-Section([string]$Title) {
  Write-Host ""
  Write-Host $Title
  Write-Host ('-' * $Title.Length)
}

function Resolve-AdbPath {
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "C:\Android\Sdk\platform-tools\adb.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) { return $candidate }
  }

  throw "No se encontró adb. Instalá Android platform-tools o configurá ANDROID_SDK_ROOT."
}

function Resolve-FlutterPath {
  $flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
  if (-not (Test-Path $flutter)) {
    throw "No se encontró Flutter en: $FlutterRoot"
  }
  return $flutter
}

function Get-AndroidDeviceId {
  param([string]$FlutterPath)

  $raw = & $FlutterPath devices 2>$null
  if (-not $raw) { return $null }

  $text = $raw -join "`n"
  $patterns = @(
    'adb-[^\s]+_adb-tls-connect\._tcp',
    'adb-[^\s]+'
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($text, $pattern)
    if ($match.Success) {
      return $match.Value.Trim()
    }
  }

  return $null
}

function Invoke-Adb {
  param(
    [Parameter(Mandatory = $true)][string]$AdbPath,
    [Parameter(Mandatory = $true)][string[]]$Args
  )

  & $AdbPath @Args
  if ($LASTEXITCODE -ne 0) {
    throw "adb falló con exit code $LASTEXITCODE al ejecutar: adb $($Args -join ' ')"
  }
}

$adbPath = Resolve-AdbPath
$flutterPath = Resolve-FlutterPath

Write-Section "Wireless Runner"
Write-Host "Este script no hace el QR de emparejamiento."
Write-Host "Si todavía no emparejaste el teléfono, hacelo desde el celular:"
Write-Host "Opciones de desarrollador -> Depuración inalámbrica -> Emparejar con código o QR"
Write-Host ""

Write-Section "Detectando dispositivo"
& $flutterPath devices

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
  $DeviceId = Get-AndroidDeviceId -FlutterPath $flutterPath
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
  throw "No se detectó ningún dispositivo Android. Si ya emparejaste por WiFi, esperá unos segundos y volvé a correr el script."
}

Write-Host "Usando device id: $DeviceId"

Write-Section "Preparando adb"
Invoke-Adb -AdbPath $adbPath -Args @('start-server')

Write-Section "Instalando dependencias"
& $flutterPath pub get
if ($LASTEXITCODE -ne 0) {
  throw "flutter pub get falló."
}

Write-Section "Dispositivos"
& $flutterPath devices

Write-Section "Ejecutando app"
& $flutterPath run -d $DeviceId
if ($LASTEXITCODE -ne 0) {
  throw "flutter run falló."
}
