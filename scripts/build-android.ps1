param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArguments = @()
)

. (Join-Path $PSScriptRoot '_project.ps1')

Push-Location $script:ProjectRoot
try {
  Assert-RepositoryIdentity
  Assert-LocalSupabaseConfig
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
  ) + $FlutterArguments
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
