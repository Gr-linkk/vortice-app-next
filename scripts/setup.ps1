param()

. (Join-Path $PSScriptRoot '_project.ps1')

Push-Location $script:ProjectRoot
try {
  Assert-RepositoryIdentity
  Invoke-ProjectCommand -Command 'flutter' -Arguments @('pub', 'get')
  Invoke-ProjectGuardrails
  Invoke-ProjectCommand -Command 'dart' -Arguments @(
    'run',
    'build_runner',
    'build'
  )
  Write-Host 'Setup complete. No remote services were changed.'
} finally {
  Pop-Location
}
