# package-sync notify — fires on terminal open, checks remote for new packages

function _pkgsync_check_remote {
    $cfgFile = "$HOME\.package-sync\config.json"
    $pkgFile = "$HOME\.package-sync\packages.json"

    if (-not (Test-Path $cfgFile) -or -not (Test-Path $pkgFile)) { return }

    $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json
    $gistId = $cfg.gist_id
    if (-not $gistId) { return }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { return }

    try {
        $content = gh api "/gists/$gistId" --jq '.files["packages.json"].content' 2>$null
        if (-not $content) { return }
        $remote = $content | ConvertFrom-Json
    } catch { return }

    $local = Get-Content $pkgFile -Raw | ConvertFrom-Json
    $localNames  = @($local.packages  | Select-Object -ExpandProperty name)
    $remoteNames = @($remote.packages | Select-Object -ExpandProperty name)

    $newPkgs = $remoteNames | Where-Object { $_ -notin $localNames }
    if (-not $newPkgs) { return }

    $count = @($newPkgs).Count
    Write-Host ''
    Write-Host "📦 package-sync: $count new package(s) on remote:"
    foreach ($pkg in $newPkgs) {
        $info = $remote.packages | Where-Object { $_.name -eq $pkg } | Select-Object -First 1
        Write-Host ("  + {0} ({1}) — from {2}" -f $info.name, $info.manager, $info.device)
    }
    Write-Host '   Run: package-sync sync pull'
    Write-Host ''
}

_pkgsync_check_remote
