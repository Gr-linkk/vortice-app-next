param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArguments = @()
)

. (Join-Path $PSScriptRoot '_project.ps1')

Push-Location $script:ProjectRoot
try {
  Assert-RepositoryIdentity
  Assert-LocalSupabaseConfig
  $runArguments = @(
    'run',
    '--dart-define-from-file=config/vortice-next.local.json'
  ) + $FlutterArguments
  Invoke-ProjectCommand -Command 'flutter' -Arguments $runArguments
} finally {
  Pop-Location
}
