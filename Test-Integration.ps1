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
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powerShell
    $escapedApp = $app.Replace('"', '\"')
    $escapedDirectory = $testDirectory.Replace('"', '\"')
    $startInfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -STA -File "{0}" "{1}"' -f $escapedApp, $escapedDirectory)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Could not start SendToImageResizer." }

    $process.StandardInput.WriteLine("3")
    $process.StandardInput.WriteLine("")
    $process.StandardInput.WriteLine("Q")
    $process.StandardInput.Close()

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "SendToImageResizer exited with code $($process.ExitCode). Output: $standardOutput Error: $standardError"
    }
    if (-not (Test-Path -LiteralPath $sourceImage -PathType Leaf)) {
        throw "The copy preset removed the source image."
    }
    if (-not (Test-Path -LiteralPath $outputImage -PathType Leaf)) {
        throw "The expected copy was not created. Output: $standardOutput Error: $standardError"
    }

    $dimensions = (& $magick identify -format "%wx%h" $outputImage).Trim()
    if ($LASTEXITCODE -ne 0 -or $dimensions -ne "2000x1500") {
        throw "Expected 2000x1500 pixels, got '$dimensions'."
    }

    Write-Host "Integration test passed: 4000x3000 -> 2000x1500 copy." -ForegroundColor Green
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

