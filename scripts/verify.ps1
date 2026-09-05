param(
  [string]$BaseRef = ''
)

. (Join-Path $PSScriptRoot '_project.ps1')

Push-Location $script:ProjectRoot
try {
  Assert-RepositoryIdentity
  Invoke-ProjectGuardrails -BaseRef $BaseRef
  Invoke-ProjectCommand -Command 'flutter' -Arguments @('pub', 'get')
  Invoke-ProjectCommand -Command 'dart' -Arguments @(
    'run',
    'build_runner',
    'build'
  )
  Invoke-ProjectCommand -Command 'flutter' -Arguments @('analyze')
  Invoke-ProjectCommand -Command 'flutter' -Arguments @('test')
  Write-Host 'Project verification passed.'
} finally {
  Pop-Location
}
