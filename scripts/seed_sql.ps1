param(
  [string]$SqlUser = $env:SQL_ADMIN_LOGIN,
  [string]$SqlPassword = $env:SQL_ADMIN_PASSWORD
)

$ErrorActionPreference = "Stop"

function Require-Command {
  param([string]$Name)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command '$Name' was not found on PATH."
  }
}

function Get-TerraformOutput {
  param(
    [string]$Dir,
    [string]$Name
  )
  $value = terraform -chdir="$Dir" output -raw $Name 2>$null
  if (-not $value) {
    throw "Missing terraform output '$Name' in '$Dir'."
  }
  return $value
}

function Get-TfvarsValue {
  param(
    [string]$Path,
    [string]$Key
  )
  if (-not (Test-Path $Path)) {
    return $null
  }
  $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+?)\s*$'
  foreach ($line in Get-Content -Path $Path) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') {
      continue
    }
    if ($line -match $pattern) {
      $raw = $Matches[1].Trim()
      if ($raw -eq "null") {
        return $null
      }
      if ($raw -match '^"(.*)"$') {
        return $Matches[1]
      }
      return $raw
    }
  }
  return $null
}

function Invoke-AzCli {
  param([string[]]$CliArgs)
  $azCmd = (Get-Command az -ErrorAction Stop).Source
  if ($azCmd -and $azCmd.ToLower().EndsWith(".cmd")) {
    $azDir = Split-Path $azCmd
    $pythonPath = Join-Path $azDir "..\\python.exe"
    if (Test-Path $pythonPath) {
      & $pythonPath -m azure.cli @CliArgs
    } else {
      & $azCmd @CliArgs
    }
  } else {
    & $azCmd @CliArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI failed with exit code $LASTEXITCODE."
  }
}

Require-Command "terraform"
Require-Command "az"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$rgDir = Join-Path $repoRoot "terraform\01_resource_group"
$sqlDir = Join-Path $repoRoot "terraform\05_private_sql"
$appDir = Join-Path $repoRoot "terraform\07_app_tier"
$seedPath = Join-Path $repoRoot "sql_scripts\vnet_demo_seed.sql"
$tfvarsPath = Join-Path $sqlDir "terraform.tfvars"

if (-not $SqlUser) {
  $SqlUser = Get-TfvarsValue -Path $tfvarsPath -Key "sql_admin_login"
}
if (-not $SqlPassword) {
  $SqlPassword = Get-TfvarsValue -Path $tfvarsPath -Key "sql_admin_password"
}

if (-not $SqlUser -or -not $SqlPassword) {
  throw "Set SQL_ADMIN_LOGIN and SQL_ADMIN_PASSWORD or pass -SqlUser and -SqlPassword."
}

if (-not (Test-Path $seedPath)) {
  throw "SQL seed script not found at $seedPath."
}

$rg = Get-TerraformOutput -Dir $rgDir -Name "resource_group_name"
$appVm = Get-TerraformOutput -Dir $appDir -Name "app_vm_name"
$sqlFqdn = Get-TerraformOutput -Dir $sqlDir -Name "sql_server_fqdn"
$sqlDb = Get-TerraformOutput -Dir $sqlDir -Name "sql_database_name"

$sqlUserB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SqlUser))
$sqlPassB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SqlPassword))
$sqlFqdnB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sqlFqdn))
$sqlDbB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sqlDb))

$cmds = @(
  "set -e",
  "SQLUSER=`$(printf '%s' '$sqlUserB64' | base64 -d)",
  "SQLPASS=`$(printf '%s' '$sqlPassB64' | base64 -d)",
  "SQLFQDN=`$(printf '%s' '$sqlFqdnB64' | base64 -d)",
  "SQLDB=`$(printf '%s' '$sqlDbB64' | base64 -d)",
  "SQLCMD_BIN=''",
  "if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD_BIN=/opt/mssql-tools18/bin/sqlcmd; elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then SQLCMD_BIN=/opt/mssql-tools/bin/sqlcmd; else",
  "  sudo apt-get update",
  "  sudo apt-get install -y curl apt-transport-https ca-certificates gnupg",
  "  curl -sS https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg >/dev/null",
  "  curl -sS https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list >/dev/null",
  "  sudo apt-get update",
  "  sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev",
  "  SQLCMD_BIN=/opt/mssql-tools18/bin/sqlcmd",
  "fi",
  "cat > /tmp/vnet_demo_seed.sql << 'EOF'"
)

$cmds += Get-Content -Path $seedPath
$cmds += @(
  "SELECT COUNT(*) AS row_count FROM dbo.demo_customers;",
  "EOF",
  '"$SQLCMD_BIN" -C -S "$SQLFQDN" -d "$SQLDB" -U "$SQLUSER" -P "$SQLPASS" -b -i /tmp/vnet_demo_seed.sql'
)

Write-Host "Seeding Azure SQL via app VM $appVm..."
$azArgs = @(
  "vm",
  "run-command",
  "invoke",
  "--resource-group",
  $rg,
  "--name",
  $appVm,
  "--command-id",
  "RunShellScript",
  "--scripts"
) + $cmds + @("--query", "value[0].message", "-o", "tsv")
Invoke-AzCli -CliArgs $azArgs
