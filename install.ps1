[CmdletBinding()]
param(
    [ValidateSet('Install', 'Upgrade', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$Version = 'latest',
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'PathWeave'),
    [string]$Repository = 'ryuabiru/PathWeave',
    [string]$PackageRoot,
    [switch]$UseTab,
    [switch]$NoPathUpdate,
    [switch]$NoProfileUpdate,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-PathWeaveNormalizedVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    if ($Version -eq 'latest') {
        return 'latest'
    }

    if ($Version.StartsWith('v')) {
        return $Version.Substring(1)
    }

    return $Version
}

function Get-PathWeaveAssetName {
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    "PathWeave-v{0}-windows-x86_64.zip" -f (Get-PathWeaveNormalizedVersion -Version $Version)
}

function Test-PathWeavePackageRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $requiredPaths = @(
        'pwv.exe',
        'powershell\PathWeave.psd1',
        'powershell\PathWeave.psm1'
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredPath))) {
            return $false
        }
    }

    return $true
}

function Resolve-PathWeaveLocalPackageRoot {
    param(
        [string]$ScriptPath,
        [string]$RequestedPackageRoot
    )

    if ($RequestedPackageRoot) {
        $resolved = (Resolve-Path -LiteralPath $RequestedPackageRoot).Path
        if (-not (Test-PathWeavePackageRoot -Path $resolved)) {
            throw "PackageRoot does not look like a PathWeave package: $resolved"
        }

        return $resolved
    }

    if (-not $ScriptPath) {
        return $null
    }

    $scriptDirectory = Split-Path -Parent $ScriptPath
    if (Test-PathWeavePackageRoot -Path $scriptDirectory) {
        return $scriptDirectory
    }

    return $null
}

function Get-PathWeaveReleaseApiUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$Version
    )

    if ($Version -eq 'latest') {
        return "https://api.github.com/repos/$Repository/releases/latest"
    }

    return "https://api.github.com/repos/$Repository/releases/tags/v$(Get-PathWeaveNormalizedVersion -Version $Version)"
}

function Get-PathWeaveRemotePackageInfo {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$Version
    )

    $headers = @{
        'User-Agent' = 'PathWeave-Installer'
    }
    $release = Invoke-RestMethod -Uri (Get-PathWeaveReleaseApiUrl -Repository $Repository -Version $Version) -Headers $headers
    $assetName = Get-PathWeaveAssetName -Version $release.tag_name
    $zipAsset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $zipAsset) {
        throw "Release asset '$assetName' was not found in $($release.tag_name)."
    }

    $shaAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1

    [pscustomobject]@{
        TagName = $release.tag_name
        AssetName = $assetName
        ZipUrl = $zipAsset.browser_download_url
        Sha256Url = $shaAsset.browser_download_url
    }
}

function Expand-PathWeaveRemotePackage {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$PackageInfo
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("PathWeave-" + [System.Guid]::NewGuid().ToString())
    $zipPath = Join-Path $tempRoot $PackageInfo.AssetName
    $extractRoot = Join-Path $tempRoot 'extract'

    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Invoke-WebRequest -Uri $PackageInfo.ZipUrl -OutFile $zipPath -Headers @{ 'User-Agent' = 'PathWeave-Installer' }

    if ($PackageInfo.Sha256Url) {
        $shaPath = Join-Path $tempRoot 'SHA256SUMS.txt'
        Invoke-WebRequest -Uri $PackageInfo.Sha256Url -OutFile $shaPath -Headers @{ 'User-Agent' = 'PathWeave-Installer' }
        $shaLines = Get-Content -LiteralPath $shaPath
        $expectedLine = $shaLines | Where-Object { $_ -match [regex]::Escape($PackageInfo.AssetName) + '$' } | Select-Object -First 1
        if ($expectedLine) {
            $expectedHash = ($expectedLine -split '\s+')[0].ToLowerInvariant()
            $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($expectedHash -ne $actualHash) {
                throw "SHA256 mismatch for $($PackageInfo.AssetName)."
            }
        }
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $packageRoot = Join-Path $extractRoot ([System.IO.Path]::GetFileNameWithoutExtension($PackageInfo.AssetName))
    if (-not (Test-PathWeavePackageRoot -Path $packageRoot)) {
        throw "Expanded package is missing expected files: $packageRoot"
    }

    [pscustomobject]@{
        Root = $packageRoot
        TempRoot = $tempRoot
    }
}

function Get-PathWeaveManagedEntries {
    @(
        'pwv.exe',
        'powershell',
        'examples',
        'README.md',
        'README_ja.md',
        'LICENSE',
        'install.ps1',
        'SHA256SUMS.txt'
    )
}

function Test-PathWeaveInstallRoot {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot
    )

    $managedEntries = Get-PathWeaveManagedEntries | Where-Object { Test-Path -LiteralPath (Join-Path $InstallRoot $_) }
    $managedEntries.Count -gt 0
}

function Copy-PathWeavePackage {
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,
        [Parameter(Mandatory)]
        [string]$InstallRoot,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $InstallRoot) -and -not $Force) {
        $existingEntries = Get-PathWeaveManagedEntries | Where-Object { Test-Path -LiteralPath (Join-Path $InstallRoot $_) }
        if ($existingEntries.Count -gt 0) {
            throw "Install root already contains a PathWeave installation. Re-run with -Force to replace it: $InstallRoot"
        }
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    foreach ($entry in Get-PathWeaveManagedEntries) {
        $destination = Join-Path $InstallRoot $entry
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }

        $source = Join-Path $SourceRoot $entry
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
        }
    }
}

function Remove-PathWeaveFromUserPath {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) {
        return
    }

    $normalizedInstallRoot = $InstallRoot.TrimEnd('\')
    $entries = $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $_.TrimEnd('\') -ine $normalizedInstallRoot }
    [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
}

function Add-PathWeaveToUserPath {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) {
        $entries = $userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
    }

    $normalizedInstallRoot = $InstallRoot.TrimEnd('\')
    $exists = $entries | Where-Object { $_.TrimEnd('\') -ieq $normalizedInstallRoot } | Select-Object -First 1
    if (-not $exists) {
        $newEntries = @($entries + $InstallRoot)
        [Environment]::SetEnvironmentVariable('Path', ($newEntries -join ';'), 'User')
    }
}

function Get-PathWeaveProfileBlock {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot,
        [switch]$UseTab
    )

    $importPath = Join-Path $InstallRoot 'powershell\PathWeave.psd1'
    $enableCommand = if ($UseTab) { 'Enable-PathWeave -UseTab' } else { 'Enable-PathWeave' }

    @(
        '# PathWeave start'
        "Import-Module '$importPath' -Force"
        $enableCommand
        '# PathWeave end'
    ) -join [Environment]::NewLine
}

function Remove-PathWeaveProfileBlock {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if (-not (Test-Path -LiteralPath $profilePath)) {
        return
    }

    $content = Get-Content -LiteralPath $profilePath -Raw
    $pattern = '(?ms)\r?\n?# PathWeave start\r?\n.*?^# PathWeave end\r?\n?'
    $newContent = [regex]::Replace($content, $pattern, '')
    $newContent = $newContent.TrimEnd("`r", "`n")

    if ([string]::IsNullOrWhiteSpace($newContent)) {
        Set-Content -LiteralPath $profilePath -Value ''
        return
    }

    Set-Content -LiteralPath $profilePath -Value ($newContent + [Environment]::NewLine)
}

function Update-PathWeaveProfile {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot,
        [switch]$UseTab
    )

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDirectory = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileDirectory)) {
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $profilePath)) {
        New-Item -ItemType File -Path $profilePath | Out-Null
    }

    $content = Get-Content -LiteralPath $profilePath -Raw
    $block = Get-PathWeaveProfileBlock -InstallRoot $InstallRoot -UseTab:$UseTab
    $pattern = '(?ms)^# PathWeave start\r?\n.*?^# PathWeave end'

    if ($content -match $pattern) {
        $newContent = [regex]::Replace($content, $pattern, $block)
    }
    elseif ([string]::IsNullOrWhiteSpace($content)) {
        $newContent = $block + [Environment]::NewLine
    }
    else {
        $trimmed = $content.TrimEnd("`r", "`n")
        $newContent = $trimmed + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine
    }

    Set-Content -LiteralPath $profilePath -Value $newContent
}

function Remove-PathWeaveInstall {
    param(
        [Parameter(Mandatory)]
        [string]$InstallRoot,
        [switch]$NoPathUpdate,
        [switch]$NoProfileUpdate,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $InstallRoot)) {
        Write-Host "PathWeave is not installed at $InstallRoot"
        return
    }

    if (-not $Force -and -not (Test-PathWeaveInstallRoot -InstallRoot $InstallRoot)) {
        throw "InstallRoot does not look like a PathWeave installation. Re-run with -Force to remove it anyway: $InstallRoot"
    }

    foreach ($entry in Get-PathWeaveManagedEntries) {
        $path = Join-Path $InstallRoot $entry
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    if (-not $NoProfileUpdate) {
        Remove-PathWeaveProfileBlock
    }

    if (-not $NoPathUpdate) {
        Remove-PathWeaveFromUserPath -InstallRoot $InstallRoot
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        $remainingEntries = Get-ChildItem -LiteralPath $InstallRoot -Force -ErrorAction SilentlyContinue
        if (-not $remainingEntries) {
            Remove-Item -LiteralPath $InstallRoot -Force
        }
    }

    Write-Host "PathWeave removed from $InstallRoot"
    if (-not $NoProfileUpdate) {
        Write-Host "PowerShell profile cleaned up."
    }
    if (-not $NoPathUpdate) {
        Write-Host "User PATH cleaned up. Open a new PowerShell session to pick it up."
    }
}

function Install-PathWeave {
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [Parameter(Mandatory)]
        [string]$InstallRoot,
        [Parameter(Mandatory)]
        [string]$Repository,
        [string]$PackageRoot,
        [switch]$UseTab,
        [switch]$NoPathUpdate,
        [switch]$NoProfileUpdate,
        [switch]$Force
    )

    $cleanupRoot = $null
    $localPackageRoot = Resolve-PathWeaveLocalPackageRoot -ScriptPath $PSCommandPath -RequestedPackageRoot $PackageRoot
    if ($localPackageRoot) {
        $sourceRoot = $localPackageRoot
        Write-Host "Using local package: $sourceRoot"
    }
    else {
        $packageInfo = Get-PathWeaveRemotePackageInfo -Repository $Repository -Version $Version
        Write-Host "Downloading $($packageInfo.TagName)..."
        $expanded = Expand-PathWeaveRemotePackage -PackageInfo $packageInfo
        $sourceRoot = $expanded.Root
        $cleanupRoot = $expanded.TempRoot
    }

    try {
        Copy-PathWeavePackage -SourceRoot $sourceRoot -InstallRoot $InstallRoot -Force:$Force

        if (-not $NoPathUpdate) {
            Add-PathWeaveToUserPath -InstallRoot $InstallRoot
        }

        if (-not $NoProfileUpdate) {
            Update-PathWeaveProfile -InstallRoot $InstallRoot -UseTab:$UseTab
        }

        Write-Host "PathWeave installed to $InstallRoot"
        if (-not $NoProfileUpdate) {
            Write-Host "PowerShell profile updated."
        }
        if (-not $NoPathUpdate) {
            Write-Host "User PATH updated. Open a new PowerShell session to pick it up."
        }
    }
    finally {
        if ($cleanupRoot -and (Test-Path -LiteralPath $cleanupRoot)) {
            Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
        }
    }
}

switch ($Action) {
    'Install' {
        Install-PathWeave `
            -Version $Version `
            -InstallRoot $InstallRoot `
            -Repository $Repository `
            -PackageRoot $PackageRoot `
            -UseTab:$UseTab `
            -NoPathUpdate:$NoPathUpdate `
            -NoProfileUpdate:$NoProfileUpdate `
            -Force:$Force
    }
    'Upgrade' {
        Install-PathWeave `
            -Version $Version `
            -InstallRoot $InstallRoot `
            -Repository $Repository `
            -PackageRoot $PackageRoot `
            -UseTab:$UseTab `
            -NoPathUpdate:$NoPathUpdate `
            -NoProfileUpdate:$NoProfileUpdate `
            -Force
    }
    'Uninstall' {
        Remove-PathWeaveInstall `
            -InstallRoot $InstallRoot `
            -NoPathUpdate:$NoPathUpdate `
            -NoProfileUpdate:$NoProfileUpdate `
            -Force:$Force
    }
}
