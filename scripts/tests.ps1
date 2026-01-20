param(
  [switch]$SeedSql,
  [switch]$SkipHealth,
  [switch]$SkipRemoteChecks,
  [string]$SqlUser,
  [string]$SqlPassword
)

$ErrorActionPreference = "Stop"

$healthScript = Join-Path $PSScriptRoot "health_check.ps1"
$seedScript = Join-Path $PSScriptRoot "seed_sql.ps1"

if (-not $SkipHealth) {
  if (-not (Test-Path $healthScript)) {
    throw "health_check.ps1 not found at $healthScript."
  }
  $healthArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $healthScript)
  if ($SkipRemoteChecks) {
    $healthArgs += "-SkipRemoteChecks"
  }
  & powershell @healthArgs
}

if ($SeedSql) {
  if (-not (Test-Path $seedScript)) {
    throw "seed_sql.ps1 not found at $seedScript."
  }
  $seedArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $seedScript)
  if ($SqlUser) {
    $seedArgs += @("-SqlUser", $SqlUser)
  }
  if ($SqlPassword) {
    $seedArgs += @("-SqlPassword", $SqlPassword)
  }
  & powershell @seedArgs
}
