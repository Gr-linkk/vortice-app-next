param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArguments = @()
)

. (Join-Path $PSScriptRoot '_project.ps1')

Push-Location $script:ProjectRoot
try {
  Assert-RepositoryIdentity
  Assert-LocalSupabaseConfig
  $firebaseArguments = @()
  if (-not [string]::IsNullOrWhiteSpace($env:VORTICE_NEXT_FIREBASE_CONFIG)) {
    $firebasePath = [IO.Path]::GetFullPath($env:VORTICE_NEXT_FIREBASE_CONFIG)
    $firebase = Get-Content -LiteralPath $firebasePath -Raw | ConvertFrom-Json
    if ($firebase.FIREBASE_PROJECT_ID -ne 'vortice-next' -or
        $firebase.FIREBASE_ANDROID_APP_ID -ne '1:256876964373:android:ba58553beed6145f033c1c' -or
        $firebase.FIREBASE_MESSAGING_SENDER_ID -ne '256876964373' -or
        [string]::IsNullOrWhiteSpace($firebase.FIREBASE_API_KEY)) {
      throw 'Firebase configuration must identify the dedicated Vortice Next Android app.'
    }
    if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue) -and $env:OS -eq 'Windows_NT') {
      $firebasePath = (& wsl.exe -e wslpath -u $firebasePath).Trim()
      if ($LASTEXITCODE -ne 0) { throw 'Could not translate the Firebase config path.' }
    }
    $firebaseArguments = @("--dart-define-from-file=$firebasePath")
  }
  # Check the values consumed by the app, not just the local JSON file.
  Invoke-ProjectCommand -Command 'flutter' -Arguments @(
    'test',
    (Get-FlutterConfigArgument),
    'test/core/backend_build_config_test.dart'
  )
  $buildArguments = @(
    'build',
    'apk',
    '--debug',
    (Get-FlutterConfigArgument)
  ) + $firebaseArguments + $FlutterArguments
  Invoke-ProjectCommand -Command 'flutter' -Arguments $buildArguments

  $source = Join-Path $script:ProjectRoot 'build/app/outputs/flutter-apk/app-debug.apk'
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Flutter reported success but the debug APK was not found.'
  }

  $outputDirectory = Join-Path $script:ProjectRoot 'outputs/builds'
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $destination = Join-Path $outputDirectory "vortice-next-android-debug-$stamp.apk"
  Copy-Item -LiteralPath $source -Destination $destination
  $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath "$destination.sha256" -Value "$hash  $([IO.Path]::GetFileName($destination))"
  Write-Host "Internal debug APK: $destination"
  Write-Host "SHA-256: $hash"
} finally {
  Pop-Location
}
