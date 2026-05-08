#Requires -Version 5.1
# Bootstrap installer for Windows
# Run: irm https://raw.githubusercontent.com/mrdaiking/package-sync/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$Repo       = 'https://github.com/mrdaiking/package-sync'
$InstallDir = Join-Path $HOME '.package-sync'
$BinDir     = Join-Path $HOME '.local\bin'

Write-Host 'package-sync installer (Windows)'
Write-Host ''

# Check jq — not required on Windows (uses native PS JSON), but warn if gh missing
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'gh CLI not found. Sync features need it.'
    Write-Host 'Install: winget install GitHub.cli'
    Write-Host ''
}

# Clone or update
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-Host 'Updating existing installation...'
    git -C $InstallDir pull --ff-only
} else {
    Write-Host "Installing to $InstallDir ..."
    git clone $Repo $InstallDir
}

# Copy ps1 to bin so `package-sync` works from PATH
if (-not (Test-Path $BinDir)) { New-Item -ItemType Directory $BinDir | Out-Null }
$wrapper = Join-Path $BinDir 'package-sync.ps1'
Copy-Item (Join-Path $InstallDir 'package-sync.ps1') $wrapper -Force

# Add bin to PATH if missing
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('PATH', "$userPath;$BinDir", 'User')
    Write-Host "Added $BinDir to PATH (restart shell to take effect)"
}

Write-Host ''
Write-Host 'Installed. Run setup:'
Write-Host '  package-sync init          # add hooks to $PROFILE'
Write-Host '  package-sync sync setup    # link GitHub Gist for cross-device sync'
Write-Host ''
Write-Host 'Restart PowerShell after init.'
