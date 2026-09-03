[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$sourceDirectory = $PSScriptRoot
$installDirectory = Join-Path $env:LOCALAPPDATA "SendToImageResizer"
$sendToDirectory = Join-Path $env:APPDATA "Microsoft\Windows\SendTo"
$startMenuDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\SendToImageResizer"
$sendToShortcut = Join-Path $sendToDirectory "Image Resizer.lnk"
$startMenuShortcut = Join-Path $startMenuDirectory "Image Resizer.lnk"
$uninstallShortcut = Join-Path $startMenuDirectory "Uninstall Image Resizer.lnk"

function New-PowerShellShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string]$Description = "SendToImageResizer"
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
    $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $ScriptPath)
    $shortcut.WorkingDirectory = Split-Path -Parent $ScriptPath
    $shortcut.Description = $Description
    $shortcut.IconLocation = (Join-Path $env:SystemRoot "System32\imageres.dll") + ",67"
    $shortcut.Save()
}

try {
    Write-Host "Installing SendToImageResizer..."

    $sourceFullPath = [System.IO.Path]::GetFullPath($sourceDirectory).TrimEnd('\')
    $installFullPath = [System.IO.Path]::GetFullPath($installDirectory).TrimEnd('\')
    $repairOnly = $sourceFullPath.Equals($installFullPath, [StringComparison]::OrdinalIgnoreCase)

    $requiredSourceFiles = @(
        "SendToImageResizer.ps1",
        "presets.json",
        "presets.default.json",
        "VERSION.txt",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "ImageMagick\magick.exe",
        "ImageMagick\LICENSE.txt",
        "ImageMagick\NOTICE.txt"
    )
    foreach ($relativePath in $requiredSourceFiles) {
        $fullPath = Join-Path $sourceDirectory $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "The package is incomplete. Missing: $relativePath"
        }
    }

    New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $sendToDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $startMenuDirectory -Force | Out-Null

    $filesToCopy = @(
        "SendToImageResizer.ps1",
        "SendToImageResizer.cmd",
        "Install.ps1",
        "Install.cmd",
        "Uninstall.ps1",
        "Uninstall.cmd",
        "presets.default.json",
        "VERSION.txt",
        "LICENSE",
        "README.md",
        "THIRD_PARTY_NOTICES.md"
    )
    if (-not $repairOnly) {
        foreach ($relativePath in $filesToCopy) {
            $sourcePath = Join-Path $sourceDirectory $relativePath
            if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $installDirectory $relativePath) -Force
            }
        }
    }

    $installedPresets = Join-Path $installDirectory "presets.json"
    if (-not (Test-Path -LiteralPath $installedPresets -PathType Leaf)) {
        Copy-Item -LiteralPath (Join-Path $sourceDirectory "presets.json") -Destination $installedPresets
    }
    else {
        Write-Host "Keeping existing user presets."
    }

    $installedImageMagick = Join-Path $installDirectory "ImageMagick"
    if (-not $repairOnly) {
        if (Test-Path -LiteralPath $installedImageMagick) {
            Remove-Item -LiteralPath $installedImageMagick -Recurse -Force
        }
        Copy-Item -LiteralPath (Join-Path $sourceDirectory "ImageMagick") -Destination $installedImageMagick -Recurse
    }
    else {
        Write-Host "Repairing shortcuts for the existing installation."
    }

    $installedScript = Join-Path $installDirectory "SendToImageResizer.ps1"
    New-PowerShellShortcut -Path $sendToShortcut -ScriptPath $installedScript -Description "Resize exactly the selected images or a selected folder"
    New-PowerShellShortcut -Path $startMenuShortcut -ScriptPath $installedScript -Description "Open SendToImageResizer"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($uninstallShortcut)
    $shortcut.TargetPath = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
    $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $installDirectory "Uninstall.ps1"))
    $shortcut.WorkingDirectory = $installDirectory
    $shortcut.Description = "Uninstall SendToImageResizer"
    $shortcut.IconLocation = (Join-Path $env:SystemRoot "System32\shell32.dll") + ",131"
    $shortcut.Save()

    Write-Host
    Write-Host "Installed to: $installDirectory" -ForegroundColor Green
    Write-Host "Send To entry: Image Resizer" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host
    Write-Host "Installation failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}
