[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$buildRoot = Join-Path $outputRoot "SendToImageResizer-build"
$packageRoot = Join-Path $buildRoot "SendToImageResizer"
$verificationRoot = Join-Path $outputRoot "SendToImageResizer-verify"
$zipPath = Join-Path $outputRoot "SendToImageResizer.zip"

$packageFiles = @(
    "Install.cmd",
    "Install.ps1",
    "Uninstall.cmd",
    "Uninstall.ps1",
    "SendToImageResizer.cmd",
    "SendToImageResizer.ps1",
    "presets.json",
    "presets.default.json",
    "VERSION.txt",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md"
)

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

foreach ($workingPath in @($buildRoot, $verificationRoot, $zipPath)) {
    if (Test-Path -LiteralPath $workingPath) {
        Remove-Item -LiteralPath $workingPath -Recurse -Force
    }
}

try {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Test-Project.ps1") -RequireImageMagick
    if ($LASTEXITCODE -ne 0) { throw "Project validation failed." }

    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    foreach ($relativePath in $packageFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination (Join-Path $packageRoot $relativePath) -Force
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "ImageMagick") -Destination $packageRoot -Recurse -Force

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal

    Expand-Archive -LiteralPath $zipPath -DestinationPath $verificationRoot -Force
    $verifiedPackage = Join-Path $verificationRoot "SendToImageResizer"
    foreach ($relativePath in $packageFiles + @("ImageMagick\magick.exe", "ImageMagick\LICENSE.txt", "ImageMagick\NOTICE.txt")) {
        if (-not (Test-Path -LiteralPath (Join-Path $verifiedPackage $relativePath) -PathType Leaf)) {
            throw "Release archive is missing: $relativePath"
        }
    }

    Write-Host "Release package created: $zipPath" -ForegroundColor Green
    Write-Output $zipPath
}
finally {
    foreach ($workingPath in @($buildRoot, $verificationRoot)) {
        if (Test-Path -LiteralPath $workingPath) {
            Remove-Item -LiteralPath $workingPath -Recurse -Force
        }
    }
}
