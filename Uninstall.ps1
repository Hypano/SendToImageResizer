[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$installDirectory = Join-Path $env:LOCALAPPDATA "SendToImageResizer"
$sendToShortcut = Join-Path $env:APPDATA "Microsoft\Windows\SendTo\Image Resizer.lnk"
$startMenuDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\SendToImageResizer"

try {
    if (-not $Force) {
        Write-Host "This removes SendToImageResizer and all locally edited presets."
        $confirmation = Read-Host "Type YES to uninstall"
        if ($confirmation -cne "YES") {
            Write-Host "Uninstall cancelled."
            exit 0
        }
    }

    if (Test-Path -LiteralPath $sendToShortcut) {
        Remove-Item -LiteralPath $sendToShortcut -Force
    }
    if (Test-Path -LiteralPath $startMenuDirectory) {
        Remove-Item -LiteralPath $startMenuDirectory -Recurse -Force
    }

    if (Test-Path -LiteralPath $installDirectory) {
        $currentScript = $MyInvocation.MyCommand.Path
        if ($currentScript.StartsWith($installDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            $escapedDirectory = $installDirectory.Replace('"', '""')
            Start-Process -FilePath "cmd.exe" -ArgumentList ("/d /c timeout /t 2 /nobreak >nul & rmdir /s /q `"{0}`"" -f $escapedDirectory) -WindowStyle Hidden
        }
        else {
            Remove-Item -LiteralPath $installDirectory -Recurse -Force
        }
    }

    Write-Host "SendToImageResizer was uninstalled." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

