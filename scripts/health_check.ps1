param(
  [switch]$SkipRemoteChecks
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

Require-Command "terraform"
Require-Command "az"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$rgDir = Join-Path $repoRoot "terraform\01_resource_group"
$appDir = Join-Path $repoRoot "terraform\07_app_tier"
$lbDir = Join-Path $repoRoot "terraform\08_load_balancer"
$webDir = Join-Path $repoRoot "terraform\09_compute_web"

$rg = Get-TerraformOutput -Dir $rgDir -Name "resource_group_name"
$appVm = Get-TerraformOutput -Dir $appDir -Name "app_vm_name"
$webVm = Get-TerraformOutput -Dir $webDir -Name "vm_name"
$appLbName = Get-TerraformOutput -Dir $appDir -Name "app_lb_name"
$webLbName = Get-TerraformOutput -Dir $lbDir -Name "load_balancer_name"
$appLbIp = Get-TerraformOutput -Dir $appDir -Name "app_lb_private_ip"
$webLbIp = Get-TerraformOutput -Dir $lbDir -Name "public_ip_address"

Write-Host "Resource group: $rg"
Write-Host "App VM: $appVm"
Write-Host "Web VM: $webVm"
Write-Host "App LB: $appLbName ($appLbIp)"
Write-Host "Web LB: $webLbName ($webLbIp)"
Write-Host ""

Write-Host "VM power states:"
$appState = az vm get-instance-view --resource-group $rg --name $appVm --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
$webState = az vm get-instance-view --resource-group $rg --name $webVm --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
Write-Host "  App VM: $appState"
Write-Host "  Web VM: $webState"
Write-Host ""

Write-Host "Load balancer probes:"
Write-Host "App LB probes:"
az network lb probe list --resource-group $rg --lb-name $appLbName -o table
Write-Host ""
Write-Host "Web LB probes:"
az network lb probe list --resource-group $rg --lb-name $webLbName -o table
Write-Host ""

if (-not $SkipRemoteChecks) {
  Write-Host "Internal app LB check from web VM:"
  $cmds = @(
    "curl -sS -m 5 http://${appLbIp}:8080/health 2>&1 || true"
  )
  az vm run-command invoke --resource-group $rg --name $webVm --command-id RunShellScript --scripts $cmds --query "value[0].message" -o tsv
  Write-Host ""

  Write-Host "Public LB check from local:"
  try {
    $resp = Invoke-WebRequest -Uri "http://$webLbIp/health" -TimeoutSec 5 -UseBasicParsing
    Write-Host ("  Status: {0} {1}" -f $resp.StatusCode, $resp.StatusDescription)
    if ($resp.Content) {
      Write-Host ("  Body: {0}" -f $resp.Content.Trim())
    }
  } catch {
    Write-Host ("  Request failed: {0}" -f $_.Exception.Message)
  }
}
