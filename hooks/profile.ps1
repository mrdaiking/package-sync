# package-sync PowerShell hook — detects install commands and prompts to track

$script:_PkgSyncLastCmd = ''

function _pkgsync_is_install_cmd([string]$cmd) {
    $cmd -match '^(winget install|pip install|pip3 install|npm install -g|npm i -g|cargo install|choco install|gem install)' -or
    $cmd -match '(iwr|Invoke-WebRequest|curl).*(iex|Invoke-Expression)'
}

function _pkgsync_extract_name([string]$cmd) {
    switch -Regex ($cmd) {
        '^winget install\s+(--id\s+)?(\S+)' { return $Matches[2] }
        '^pip3?\s+install\s+(\S+)'           { return $Matches[1] }
        '^npm (install|i) -g\s+(\S+)'        { return $Matches[2] }
        '^cargo install\s+(\S+)'             { return $Matches[1] }
        '^choco install\s+(\S+)'             { return $Matches[1] }
        '^gem install\s+(\S+)'               { return $Matches[1] }
    }
    return ''
}

function _pkgsync_extract_manager([string]$cmd) {
    switch -Regex ($cmd) {
        '^winget'                              { return 'winget' }
        '^pip'                                 { return 'pip' }
        '^npm'                                 { return 'npm' }
        '^cargo'                               { return 'cargo' }
        '^choco'                               { return 'choco' }
        '^gem'                                 { return 'gem' }
        '(iwr|Invoke-WebRequest|curl).*iex'   { return 'curl' }
    }
    return 'unknown'
}

function _pkgsync_extract_url([string]$cmd) {
    if ($cmd -match 'https?://[^\s|]+') { return $Matches[0] }
    return ''
}

function _pkgsync_run_add([string]$name, [string]$manager, [string]$url = '') {
    $ps1 = "$HOME\.package-sync\package-sync.ps1"
    if (Test-Path $ps1) {
        & $ps1 add $name $manager $url
    } elseif (Get-Command package-sync -ErrorAction SilentlyContinue) {
        package-sync add $name $manager $url
    } else {
        Write-Host "package-sync not found. Run manually: package-sync add $name $manager"
    }
}

function _pkgsync_prompt_hook([string]$cmd) {
    $manager = _pkgsync_extract_manager $cmd

    # curl/iwr — ask for name + capture URL
    if ($manager -eq 'curl') {
        $url = _pkgsync_extract_url $cmd
        Write-Host ''
        Write-Host '📦 package-sync: Detected web install.'
        if ($url) { Write-Host "   URL: $url" }
        $name = Read-Host '   What did you install? (empty to skip)'
        if ($name) { _pkgsync_run_add $name 'curl' $url }
        return
    }

    $name = _pkgsync_extract_name $cmd
    if (-not $name) { return }

    Write-Host ''
    Write-Host "📦 package-sync: Add '$name' to your backup?"
    $choice = Read-Host '   Add now? [y/N]'
    if ($choice -match '^[yY]') {
        _pkgsync_run_add $name $manager
    }
}

# Notify hook — check remote on terminal open
$_notifyScript = "$HOME\.package-sync\hooks\notify.ps1"
if (Test-Path $_notifyScript) { . $_notifyScript }

# Override prompt to hook into command detection
$script:_OriginalPrompt = $function:prompt

function global:prompt {
    $lastCmd = (Get-History -Count 1 -ErrorAction SilentlyContinue)?.CommandLine
    if ($lastCmd -and $lastCmd -ne $script:_PkgSyncLastCmd) {
        $script:_PkgSyncLastCmd = $lastCmd
        if (_pkgsync_is_install_cmd $lastCmd) {
            _pkgsync_prompt_hook $lastCmd
        }
    }
    if ($script:_OriginalPrompt) {
        & $script:_OriginalPrompt
    } else {
        "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
    }
}
