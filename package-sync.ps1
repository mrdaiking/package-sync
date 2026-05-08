#Requires -Version 5.1
# package-sync — cross-device package backup & sync (Windows PowerShell)

$ErrorActionPreference = 'Stop'

$script:Version    = '0.1.0'
$script:PkgSyncDir = if ($env:PKGSYNC_DIR) { $env:PKGSYNC_DIR } else { Join-Path $HOME '.package-sync' }
$script:PkgFile    = Join-Path $script:PkgSyncDir 'packages.json'
$script:CfgFile    = Join-Path $script:PkgSyncDir 'config.json'

# ── helpers ──────────────────────────────────────────────────────────────────

function Get-Platform { 'windows' }

function Read-PkgFile {
    if (-not (Test-Path $script:PkgFile)) { return $null }
    Get-Content $script:PkgFile -Raw | ConvertFrom-Json
}

function Write-PkgFile($data) {
    # ConvertTo-Json collapses single-item arrays — force array with @()
    $json = [PSCustomObject]@{
        version  = $data.version
        packages = @($data.packages)
    } | ConvertTo-Json -Depth 10
    $tmp = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $json -Encoding UTF8
    Move-Item -Force $tmp $script:PkgFile
}

function Ensure-Init {
    if (-not (Test-Path $script:PkgSyncDir)) { New-Item -ItemType Directory -Path $script:PkgSyncDir | Out-Null }
    if (-not (Test-Path $script:PkgFile)) {
        [PSCustomObject]@{ version = $script:Version; packages = @() } |
            ConvertTo-Json -Depth 10 | Set-Content $script:PkgFile -Encoding UTF8
    }
    if (-not (Test-Path $script:CfgFile)) {
        [PSCustomObject]@{ gist_id = ''; device = $env:COMPUTERNAME } |
            ConvertTo-Json | Set-Content $script:CfgFile -Encoding UTF8
    }
}

function Get-GistId {
    if (-not (Test-Path $script:CfgFile)) { return '' }
    (Get-Content $script:CfgFile -Raw | ConvertFrom-Json).gist_id
}

function Set-GistId($id) {
    $cfg = Get-Content $script:CfgFile -Raw | ConvertFrom-Json
    $cfg | Add-Member -Force -NotePropertyName gist_id -NotePropertyValue $id
    $cfg | ConvertTo-Json | Set-Content $script:CfgFile -Encoding UTF8
}

function Require-Gh {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error 'gh CLI not installed. Run: winget install GitHub.cli'
    }
}

# ── commands ─────────────────────────────────────────────────────────────────

function Invoke-Init {
    Ensure-Init

    $hooksDir = Join-Path $script:PkgSyncDir 'hooks'
    if (-not (Test-Path $hooksDir)) { New-Item -ItemType Directory $hooksDir | Out-Null }

    # Resolve hooks source: prefer PkgSyncDir (git clone), fall back to script location
    $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
    $srcDir = if (Test-Path (Join-Path $script:PkgSyncDir 'hooks\profile.ps1')) {
        $script:PkgSyncDir
    } else {
        $scriptDir
    }

    $profileSrc = Join-Path $srcDir 'hooks\profile.ps1'
    $notifySrc  = Join-Path $srcDir 'hooks\notify.ps1'

    if (Test-Path $profileSrc) { Copy-Item $profileSrc (Join-Path $hooksDir 'profile.ps1') -Force }
    if (Test-Path $notifySrc)  { Copy-Item $notifySrc  (Join-Path $hooksDir 'notify.ps1')  -Force }

    $hookLine = '. "$HOME\.package-sync\hooks\profile.ps1"'
    $profilePath = $PROFILE

    if (-not (Test-Path $profilePath)) { New-Item -Force $profilePath | Out-Null }

    $content = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match 'package-sync') {
        Write-Host "Hook already in $profilePath"
    } else {
        Add-Content $profilePath "`n# package-sync hook`n$hookLine"
        Write-Host "Hook added to $profilePath"
    }

    Write-Host "Initialized. Restart PowerShell or run: . `$PROFILE"
}

function Invoke-Add {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Manager = 'winget',
        [string]$Url = ''
    )
    Ensure-Init

    $data = Read-PkgFile
    $exists = $data.packages | Where-Object { $_.name -eq $Name -and $_.manager -eq $Manager }
    if ($exists) {
        Write-Host "$Name ($Manager) already tracked."
        return
    }

    $entry = [PSCustomObject]@{
        name     = $Name
        manager  = $Manager
        platform = Get-Platform
        device   = $env:COMPUTERNAME
        added    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($Url) { $entry | Add-Member -NotePropertyName url -NotePropertyValue $Url }

    $data.packages = @($data.packages) + $entry
    Write-PkgFile $data

    if ($Url) { Write-Host "Added: $Name (curl) -> $Url" }
    else       { Write-Host "Added: $Name ($Manager)" }
}

function Invoke-Remove {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Manager = ''
    )
    Ensure-Init

    $data = Read-PkgFile
    if ($Manager) {
        $data.packages = @($data.packages | Where-Object { -not ($_.name -eq $Name -and $_.manager -eq $Manager) })
    } else {
        $data.packages = @($data.packages | Where-Object { $_.name -ne $Name })
    }
    Write-PkgFile $data
    Write-Host "Removed: $Name"
}

function Invoke-List {
    param([string]$Filter = 'all')
    Ensure-Init

    $data = Read-PkgFile
    $pkgs = $data.packages

    if ($Filter -ne 'all') { $pkgs = $pkgs | Where-Object { $_.manager -eq $Filter } }

    $pkgs | Sort-Object manager, name | ForEach-Object {
        $url = if ($_.url) { " | $($_.url)" } else { '' }
        "{0,-10} {1,-30} [{2}] — {3} @ {4}{5}" -f $_.manager, $_.name, $_.platform, $_.device, $_.added, $url
    }
}

function Invoke-Install {
    Ensure-Init
    $platform = Get-Platform
    $data = Read-PkgFile

    $pkgs = $data.packages | Where-Object { $_.platform -eq $platform -or $_.platform -eq 'all' }

    foreach ($pkg in $pkgs) {
        Write-Host "-> [$($pkg.manager)] $($pkg.name)"
        switch ($pkg.manager) {
            'winget' { winget install --id $pkg.name --silent }
            'pip'    { pip install $pkg.name }
            'npm'    { npm install -g $pkg.name }
            'cargo'  { cargo install $pkg.name }
            'choco'  { choco install $pkg.name -y }
            'curl'   {
                if ($pkg.url) {
                    Write-Host "  Running: iwr $($pkg.url) | iex"
                    Invoke-Expression (Invoke-RestMethod $pkg.url)
                } else {
                    Write-Host "  SKIP: $($pkg.name) — no URL stored."
                }
            }
            default  { Write-Host "  Unknown manager: $($pkg.manager). Skip." }
        }
    }
    Write-Host 'Done.'
}

function Invoke-Scan {
    Ensure-Init
    $data = Read-PkgFile
    $tracked = @($data.packages | Select-Object -ExpandProperty name)

    $untracked = [System.Collections.Generic.List[hashtable]]::new()

    # winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $tmp = [System.IO.Path]::GetTempFileName() + '.json'
        winget export -o $tmp --silent 2>$null | Out-Null
        if (Test-Path $tmp) {
            $wdata = Get-Content $tmp -Raw | ConvertFrom-Json
            foreach ($src in $wdata.Sources) {
                foreach ($pkg in $src.Packages) {
                    $id = $pkg.PackageIdentifier
                    if ($id -notin $tracked) {
                        $untracked.Add(@{ manager = 'winget'; name = $id })
                    }
                }
            }
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    }

    # pip
    if (Get-Command pip -ErrorAction SilentlyContinue) {
        pip list --format=freeze 2>$null | ForEach-Object {
            $n = ($_ -split '==')[0].ToLower()
            if ($n -and $n -notin $tracked) {
                $untracked.Add(@{ manager = 'pip'; name = $n })
            }
        }
    }

    # npm global
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm list -g --depth=0 --parseable 2>$null | Select-Object -Skip 1 | ForEach-Object {
            $n = Split-Path $_ -Leaf
            if ($n -and $n -notin $tracked) {
                $untracked.Add(@{ manager = 'npm'; name = $n })
            }
        }
    }

    if ($untracked.Count -eq 0) {
        Write-Host 'All installed packages already tracked.'
        return
    }

    Write-Host ''
    Write-Host "Found $($untracked.Count) untracked package(s):"
    Write-Host ''

    for ($i = 0; $i -lt $untracked.Count; $i++) {
        $e = $untracked[$i]
        Write-Host ("  [{0,3}] ({1,-10}) {2}" -f ($i + 1), $e.manager, $e.name)
    }

    Write-Host ''
    Write-Host '  a   — add all'
    Write-Host '  1,3 — add by number (comma-separated)'
    Write-Host '  q   — quit'
    Write-Host ''
    $choice = Read-Host 'Choice'

    switch -Regex ($choice.Trim()) {
        '^(q|Q|)$' { Write-Host 'Skipped.' }
        '^(a|A)$'  {
            foreach ($e in $untracked) { Invoke-Add -Name $e.name -Manager $e.manager }
        }
        default {
            $choice -split ',' | ForEach-Object {
                $idx = $_.Trim()
                if ($idx -match '^\d+$') {
                    $i = [int]$idx - 1
                    if ($i -ge 0 -and $i -lt $untracked.Count) {
                        $e = $untracked[$i]
                        Invoke-Add -Name $e.name -Manager $e.manager
                    } else { Write-Host "Invalid: $idx — skip" }
                } else { Write-Host "Invalid: $idx — skip" }
            }
        }
    }
}

function Invoke-Sync {
    param([string]$SubCmd = 'push', [string]$GistIdArg = '')
    Ensure-Init
    Require-Gh

    $gistId = Get-GistId

    switch ($SubCmd) {
        'setup' {
            if ($GistIdArg) {
                Set-GistId $GistIdArg
                Write-Host "Linked gist: $GistIdArg"
            } else {
                $url = gh gist create $script:PkgFile --desc 'package-sync backup' --filename 'packages.json'
                $newId = Split-Path $url -Leaf
                Set-GistId $newId
                Write-Host "Created gist: $newId"
                Write-Host "Share this ID with other devices: package-sync sync setup $newId"
            }
        }
        'push' {
            if (-not $gistId) { Write-Error 'No gist configured. Run: package-sync sync setup' }
            gh gist edit $gistId --filename packages.json $script:PkgFile
            Write-Host "Pushed -> gist:$gistId"
        }
        'pull' {
            if (-not $gistId) { Write-Error 'No gist configured. Run: package-sync sync setup' }
            $content = gh api "/gists/$gistId" --jq '.files["packages.json"].content'
            $tmp = [System.IO.Path]::GetTempFileName()
            Set-Content $tmp $content -Encoding UTF8
            try { $content | ConvertFrom-Json | Out-Null } catch { Write-Error 'Remote content invalid JSON. Run: package-sync sync push first.' }
            Move-Item -Force $tmp $script:PkgFile
            Write-Host "Pulled <- gist:$gistId"
        }
        'status' {
            if (-not $gistId) { Write-Error 'No gist configured.' }
            $content = gh api "/gists/$gistId" --jq '.files["packages.json"].content'
            $remote = $content | ConvertFrom-Json
            $data = Read-PkgFile
            $localNames  = @($data.packages | Select-Object -ExpandProperty name | Sort-Object)
            $remoteNames = @($remote.packages | Select-Object -ExpandProperty name | Sort-Object)
            $onlyRemote = $remoteNames | Where-Object { $_ -notin $localNames }
            $onlyLocal  = $localNames  | Where-Object { $_ -notin $remoteNames }

            Write-Host '=== Remote packages not on this device ==='
            $onlyRemote | ForEach-Object { Write-Host "  + $_" }
            Write-Host '=== Local packages not on remote ==='
            $onlyLocal  | ForEach-Object { Write-Host "  + $_" }
        }
        default { Write-Host 'Usage: package-sync sync [setup [gist-id]|push|pull|status]' }
    }
}

function Show-Help {
    @"
package-sync v$($script:Version) — cross-device package backup & sync

Commands:
  init                        Set up hooks in your PowerShell profile
  add <name> [manager] [url]  Track a package (default manager: winget)
  remove <name> [manager]     Stop tracking a package
  list [manager]              List tracked packages
  scan                        Scan installed packages, add untracked ones
  install                     Install all packages on new device
  sync setup [gist-id]        Create or link GitHub Gist for sync
  sync push                   Push local list to Gist
  sync pull                   Pull list from Gist
  sync status                 Show diff between local and remote

Supported managers: winget, pip, npm, cargo, choco, curl
"@
}

# ── entry point ───────────────────────────────────────────────────────────────

$cmd  = if ($args.Count -gt 0) { $args[0] } else { 'help' }
$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

function _val($arr, $i, $default = '') {
    if ($arr.Count -gt $i -and $null -ne $arr[$i] -and $arr[$i] -ne '') { $arr[$i] } else { $default }
}

switch ($cmd) {
    'init'    { Invoke-Init }
    'add'     { Invoke-Add    -Name $rest[0] -Manager (_val $rest 1 'winget') -Url (_val $rest 2) }
    'remove'  { Invoke-Remove -Name $rest[0] -Manager (_val $rest 1) }
    'list'    { Invoke-List   -Filter (_val $rest 0 'all') }
    'scan'    { Invoke-Scan }
    'install' { Invoke-Install }
    'sync'    { Invoke-Sync   -SubCmd (_val $rest 0 'push') -GistIdArg (_val $rest 1) }
    { $_ -in '--version', '-v' } { Write-Host "package-sync v$($script:Version)" }
    default   { Show-Help }
}
