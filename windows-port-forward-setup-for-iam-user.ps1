<# 
.SYNOPSIS
  Sets up AWS CLI + Session Manager Plugin (if needed), configures credentials from JSON,
  verifies identity, and starts SSM port forwarding.

.USAGE
  .\Start-SsmPortForward.ps1 -ConfigPath .\setup-config.json

.EXPECTED JSON KEYS
  {
    "accessKeyId": "AKIA...",
    "secretAccessKey": "xxxxxxxx",
    "region": "eu-west-2",
    "localPort": 3389,
    "instanceId": "i-0123456789abcdef0",
    "targetPort": 3389
  }
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

function Assert-Admin {
  $cur = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pri = New-Object Security.Principal.WindowsPrincipal($cur)
  if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script installs software. Please run PowerShell **as Administrator**."
    throw "Administrator privileges required."
  }
}

function Test-CommandExists([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-External {
  param(
    [Parameter(Mandatory=$true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [switch]$IgnoreExitCode
  )
  # Run and surface stdout/stderr
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = ($ArgumentList -join ' ')
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()
  $stdOut = $p.StandardOutput.ReadToEnd()
  $stdErr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if (-not $IgnoreExitCode -and $p.ExitCode -ne 0) {
    if ($stdOut) { Write-Host $stdOut }
    if ($stdErr) { Write-Host $stdErr }
    throw "Command failed ($FilePath): exit $($p.ExitCode)"
  }
  if ($stdOut) { Write-Host $stdOut.Trim() }
  if ($stdErr) { Write-Host $stdErr.Trim() }
  return $p.ExitCode
}

function Install-AwsCliV2 {
  if (Test-CommandExists 'aws') {
    return
  }
  Write-Host "Installing AWS CLI v2..."
  if (-not (Test-Path "AWSCLIV2.msi")) {
    $msiUrl = "https://awscli.amazonaws.com/AWSCLIV2.msi"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $msiUrl -OutFile "AWSCLIV2.msi"
  }
  Start-Process "msiexec.exe" -ArgumentList "/i `"AWSCLIV2.msi`"" -Wait
  # Refresh environment variables from the machine and user scopes
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
             [System.Environment]::GetEnvironmentVariable("Path","User")
  if (-not (Test-CommandExists 'aws')) {
    throw "AWS CLI installation appears to have failed."
  }
}

function Verify-AwsCli {
  Write-Host "Verifying AWS CLI..."
  Invoke-External -FilePath "aws" -ArgumentList "--version" -IgnoreExitCode
}

function Install-SessionManagerPlugin {
  if (Test-CommandExists 'session-manager-plugin') {
    return
  }
  Write-Host "Installing AWS Session Manager Plugin..."
  if (-not (Test-Path "SessionManagerPluginSetup.exe")) {
    $exeUrl = "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $exeUrl -OutFile "SessionManagerPluginSetup.exe"
  }
  Start-Process "SessionManagerPluginSetup.exe" -Wait
  # Refresh environment variables from the machine and user scopes
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
             [System.Environment]::GetEnvironmentVariable("Path","User")
  if (-not (Test-CommandExists 'session-manager-plugin')) {
    throw "Session Manager Plugin installation appears to have failed."
  }
}

function Verify-SessionManagerPlugin {
  Write-Host "Verifying Session Manager Plugin..."
  try {
    Invoke-External -FilePath "session-manager-plugin" -ArgumentList "--version" -IgnoreExitCode
  } catch {
    # Some versions return non-zero on --version; at least ensure the binary runs.
    Invoke-External -FilePath "session-manager-plugin" -ArgumentList "" -IgnoreExitCode
  }
}

function Read-Config([string]$Path) {
  if (-not (Test-Path $Path)) { throw "Config file not found: $Path" }
  try {
    $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json
  } catch {
    throw "Failed to parse JSON config at $Path. $_"
  }
  $required = @("accessKeyId","secretAccessKey","region","localPort","instanceId","targetPort")
  $missing = $required | Where-Object { -not $cfg.PSObject.Properties.Name.Contains($_) -or -not $cfg.$_ }
  if ($missing.Count -gt 0) {
    throw "Missing required keys in config: $($missing -join ', ')"
  }
  return $cfg
}

function Configure-Aws([object]$Cfg) {
  Write-Host "Configuring AWS credentials..."
  Invoke-External -FilePath "aws" -ArgumentList @("configure","set","aws_access_key_id",$Cfg.accessKeyId)
  Invoke-External -FilePath "aws" -ArgumentList @("configure","set","aws_secret_access_key",$Cfg.secretAccessKey)
  Invoke-External -FilePath "aws" -ArgumentList @("configure","set","region",$Cfg.region)
  Invoke-External -FilePath "aws" -ArgumentList @("configure","set","output","json")
}

function Verify-CallerIdentity([object]$Cfg) {
  Write-Host "Verifying AWS identity (sts get-caller-identity)..."
  Invoke-External -FilePath "aws" -ArgumentList @("sts","get-caller-identity","--region",$Cfg.region)
}

function Start-PortForward([object]$Cfg) {
  Write-Host "Starting SSM port forwarding..."
  $args = @(
    "ssm","start-session",
    "--region",$Cfg.region,
    "--target",$Cfg.instanceId,
    "--document-name","AWS-StartPortForwardingSession",
    "--parameters","portNumber=$($Cfg.targetPort),localPortNumber=$($Cfg.localPort)"
  )
  Write-Host "Command: aws $($args -join ' ')"
  Write-Host ""
  Write-Host "NOTE: Keep this window open while you are connected."
  Write-Host ""
  # Start the session in the current console so the tunnel stays open
  & aws @args
}

# ---------- Main ----------
try {
  Assert-Admin

  $cfg = Read-Config -Path $ConfigPath

  Install-AwsCliV2
  Verify-AwsCli

  Install-SessionManagerPlugin
  Verify-SessionManagerPlugin

  Configure-Aws -Cfg $cfg
  Verify-CallerIdentity -Cfg $cfg

  Start-PortForward -Cfg $cfg
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
