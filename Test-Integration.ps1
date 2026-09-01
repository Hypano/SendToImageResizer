[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$magick = Join-Path $PSScriptRoot "ImageMagick\magick.exe"
$app = Join-Path $PSScriptRoot "SendToImageResizer.ps1"
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("SendToImageResizer-Test-" + [Guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Path $testDirectory | Out-Null
    $sourceImage = Join-Path $testDirectory "sample image.jpg"
    $outputImage = Join-Path $testDirectory "sample image_50pct.jpg"

    & $magick -size "4000x3000" "gradient:#235789-#f1d302" -quality 92 $sourceImage
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sourceImage -PathType Leaf)) {
        throw "Could not create the integration-test image."
    }

    $powerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $appOutput = @(& $powerShell -NoProfile -ExecutionPolicy Bypass -STA -File $app -PresetName "Resize to 50%" -MainFolder $testDirectory 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "SendToImageResizer exited with code $LASTEXITCODE. Output: $($appOutput -join ' ')"
    }
    if (-not (Test-Path -LiteralPath $sourceImage -PathType Leaf)) {
        throw "The copy preset removed the source image."
    }
    if (-not (Test-Path -LiteralPath $outputImage -PathType Leaf)) {
        throw "The expected copy was not created. Output: $($appOutput -join ' ')"
    }

    $dimensions = (& $magick identify -format "%wx%h" $outputImage).Trim()
    if ($LASTEXITCODE -ne 0 -or $dimensions -ne "2000x1500") {
        throw "Expected 2000x1500 pixels, got '$dimensions'."
    }

    $replaceDirectory = Join-Path $testDirectory "replace-case"
    New-Item -ItemType Directory -Path $replaceDirectory | Out-Null
    $replaceImage = Join-Path $replaceDirectory "replace me.jpg"
    & $magick -size "640x480" "gradient:#111111-#eeeeee" -quality 95 $replaceImage
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $replaceImage -PathType Leaf)) {
        throw "Could not create the replace-test image."
    }

    $replaceOutput = @(& $powerShell -NoProfile -ExecutionPolicy Bypass -STA -File $app -PresetName "Compress (replace original)" -MainFolder $replaceDirectory 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $replaceImage -PathType Leaf)) {
        throw "Replace preset failed without confirmation. Output: $($replaceOutput -join ' ')"
    }

    Write-Host "Integration test passed: copy resize and direct safe replacement." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "Integration test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
