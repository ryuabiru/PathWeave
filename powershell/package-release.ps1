[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutputRoot = 'dist',
    [switch]$SkipTests,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

function Get-CargoVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path
    foreach ($line in $content) {
        if ($line -match '^version\s*=\s*"(?<value>[^"]+)"') {
            return $Matches.value
        }
    }

    throw "Could not find version in $Path."
}

function Get-ModuleVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path
    foreach ($line in $content) {
        if ($line -match "^\s*ModuleVersion\s*=\s*'(?<value>[^']+)'") {
            return $Matches.value
        }
    }

    throw "Could not find ModuleVersion in $Path."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cargoToml = Join-Path $repoRoot 'Cargo.toml'
$moduleManifest = Join-Path $repoRoot 'powershell\PathWeave.psd1'

$cargoVersion = Get-CargoVersion -Path $cargoToml
$moduleVersion = Get-ModuleVersion -Path $moduleManifest

if ($cargoVersion -ne $moduleVersion) {
    throw "Version mismatch: Cargo.toml=$cargoVersion, PathWeave.psd1=$moduleVersion"
}

$releaseVersion = if ($PSBoundParameters.ContainsKey('Version')) { $Version } else { $cargoVersion }
if ($releaseVersion -ne $cargoVersion) {
    throw "Requested version '$releaseVersion' does not match Cargo.toml version '$cargoVersion'."
}

Push-Location $repoRoot
try {
    if (-not $SkipTests) {
        Write-Host "Running Rust tests..."
        cargo test
        if ($LASTEXITCODE -ne 0) {
            throw 'cargo test failed.'
        }

        Write-Host "Running PowerShell tests..."
        pwsh -NoProfile -File powershell\tests\run-tests.ps1
        if ($LASTEXITCODE -ne 0) {
            throw 'PowerShell tests failed.'
        }
    }

    if (-not $SkipBuild) {
        Write-Host "Building release binary..."
        cargo build --release
        if ($LASTEXITCODE -ne 0) {
            throw 'cargo build --release failed.'
        }
    }

    $binaryPath = Join-Path $repoRoot 'target\release\pwv.exe'
    if (-not (Test-Path -LiteralPath $binaryPath)) {
        throw "Release binary not found: $binaryPath"
    }

    $outputRootPath = Join-Path $repoRoot $OutputRoot
    $packageName = "PathWeave-v$releaseVersion-windows-x86_64"
    $stagingRoot = Join-Path $outputRootPath $packageName
    $zipPath = Join-Path $outputRootPath "$packageName.zip"

    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    New-Item -ItemType Directory -Path $stagingRoot | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'powershell') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $stagingRoot 'examples') | Out-Null

    Copy-Item -LiteralPath $binaryPath -Destination (Join-Path $stagingRoot 'pwv.exe')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'powershell\PathWeave.psd1') -Destination (Join-Path $stagingRoot 'powershell\PathWeave.psd1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'powershell\PathWeave.psm1') -Destination (Join-Path $stagingRoot 'powershell\PathWeave.psm1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'examples\Microsoft.PowerShell_profile.ps1') -Destination (Join-Path $stagingRoot 'examples\Microsoft.PowerShell_profile.ps1')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $stagingRoot 'README.md')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'README_ja.md') -Destination (Join-Path $stagingRoot 'README_ja.md')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stagingRoot 'LICENSE')

    Compress-Archive -Path $stagingRoot -DestinationPath $zipPath -Force

    [pscustomobject]@{
        Version = $releaseVersion
        PackageName = $packageName
        ZipPath = $zipPath
        BinaryPath = $binaryPath
    } | Format-List
}
finally {
    Pop-Location
}
