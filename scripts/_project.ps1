Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ExpectedOrigin = 'https://github.com/Gr-linkk/vortice-app-next'
$script:ExpectedSupabaseUrl = 'https://hkjpojobdbbtjkhaudki.supabase.co'
$script:LocalConfigPath = if ([string]::IsNullOrWhiteSpace($env:VORTICE_NEXT_CONFIG)) {
  Join-Path $script:ProjectRoot 'config/vortice-next.local.json'
} else {
  [IO.Path]::GetFullPath($env:VORTICE_NEXT_CONFIG)
}

function Get-FlutterConfigArgument {
  # Reuse an explicitly selected Next configuration without copying credentials
  # into isolated worktrees. The target is checked by Assert-LocalSupabaseConfig.
  $configPath = $script:LocalConfigPath
  if ($null -eq (Get-Command flutter -ErrorAction SilentlyContinue) -and $env:OS -eq 'Windows_NT') {
    $configPath = (& wsl.exe -e wslpath -u $configPath).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not translate the selected config path.' }
  }
  return "--dart-define-from-file=$configPath"
}

function Invoke-ProjectCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )

  $nativeCommand = Get-Command $Command -ErrorAction SilentlyContinue
  if ($null -ne $nativeCommand) {
    & $Command @Arguments
  } elseif ($env:OS -eq 'Windows_NT' -and $Command -in @('dart', 'flutter')) {
    $wslCommand = "/home/garrett/.local/bin/$Command"
    & wsl.exe --cd $script:ProjectRoot -e $wslCommand @Arguments
  } else {
    throw "Required command is unavailable: $Command"
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
  }
}

function Assert-RepositoryIdentity {
  $root = (& git -C $script:ProjectRoot rev-parse --show-toplevel).Trim()
  if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($root) -ne [IO.Path]::GetFullPath($script:ProjectRoot)) {
    throw 'This command is not running in the expected repository root.'
  }

  $remotes = @(& git -C $script:ProjectRoot remote)
  if ($LASTEXITCODE -ne 0 -or $remotes.Count -ne 1 -or $remotes[0] -ne 'origin') {
    throw "Expected exactly one Git remote named origin; found: $($remotes -join ', ')"
  }

  foreach ($direction in @('fetch', 'push')) {
    $remoteArguments = @('remote', 'get-url', '--all', 'origin')
    if ($direction -eq 'push') { $remoteArguments = @('remote', 'get-url', '--push', '--all', 'origin') }
    $urls = @(& git -C $script:ProjectRoot @remoteArguments)
    if ($LASTEXITCODE -ne 0 -or $urls.Count -eq 0) { throw 'Could not verify origin URLs.' }
    foreach ($url in $urls) {
      if ((Get-NormalizedUrl $url) -ne (Get-NormalizedUrl $script:ExpectedOrigin)) {
        throw 'Every origin fetch and push URL must target the independent repository.'
      }
    }
  }
}

function Get-NormalizedUrl {
  param([Parameter(Mandatory = $true)][string]$Url)
  return ($Url.Trim().TrimEnd('/') -replace '\.git$', '').ToLowerInvariant()
}

function Assert-LocalSupabaseConfig {
  if (-not (Test-Path -LiteralPath $script:LocalConfigPath -PathType Leaf)) {
    throw "Missing local config. Copy config/vortice-next.example.json to config/vortice-next.local.json and add the public client key."
  }

  $config = Get-Content -LiteralPath $script:LocalConfigPath -Raw | ConvertFrom-Json
  if ($config.SUPABASE_URL -ne $script:ExpectedSupabaseUrl) {
    throw "Local config targets an unauthorized Supabase URL. Expected $script:ExpectedSupabaseUrl"
  }

  $clientKey = [string]$config.SUPABASE_ANON_KEY
  if ([string]::IsNullOrWhiteSpace($clientKey) -or $clientKey -match 'YOUR-|PLACEHOLDER') {
    throw 'Local config is missing a usable Supabase publishable/anon key.'
  }
}

function Invoke-ProjectGuardrails {
  param([string]$BaseRef = '')
  $arguments = @('run', 'tool/project_guardrails.dart')
  if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
    $arguments += @('--base-ref', $BaseRef)
  }
  Invoke-ProjectCommand -Command 'dart' -Arguments $arguments
}
