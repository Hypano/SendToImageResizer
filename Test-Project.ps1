[CmdletBinding()]
param(
    [switch]$RequireImageMagick
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-ValidationError {
    param([string]$Message)
    $script:errors.Add($Message)
}

$requiredFiles = @(
    "SendToImageResizer.ps1",
    "SendToImageResizer.cmd",
    "Install.ps1",
    "Install.cmd",
    "Uninstall.ps1",
    "Uninstall.cmd",
    "presets.json",
    "presets.default.json",
    "VERSION.txt",
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md"
    "Test-Integration.ps1"
)

foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $relativePath) -PathType Leaf)) {
        Add-ValidationError "Missing required file: $relativePath"
    }
}

$tokens = $null
$parseErrors = $null
foreach ($scriptName in @("SendToImageResizer.ps1", "Install.ps1", "Uninstall.ps1", "Test-Project.ps1", "Test-Integration.ps1")) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Add-ValidationError ("{0}:{1}:{2} {3}" -f $scriptName, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message)
    }
}

foreach ($configName in @("presets.json", "presets.default.json")) {
    $configPath = Join-Path $PSScriptRoot $configName
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.schemaVersion -ne 1) { Add-ValidationError "$configName uses an unsupported schemaVersion." }
        if (@($config.supportedExtensions).Count -eq 0) { Add-ValidationError "$configName has no supportedExtensions." }
        $presets = @($config.presets)
        if ($presets.Count -eq 0) { Add-ValidationError "$configName has no presets." }
        foreach ($preset in $presets) {
            if ([string]::IsNullOrWhiteSpace([string]$preset.name)) { Add-ValidationError "$configName contains a preset without a name." }
            if ([string]$preset.mode -notin @("none", "percent", "fit")) { Add-ValidationError "$configName contains an invalid resize mode." }
            if ([string]$preset.operation -notin @("copy", "replace")) { Add-ValidationError "$configName contains an invalid operation." }
            if ([int]$preset.quality -lt 1 -or [int]$preset.quality -gt 100) { Add-ValidationError "$configName contains an invalid quality." }
            if ([string]$preset.mode -eq "percent" -and ([int]$preset.value -lt 1 -or [int]$preset.value -gt 100)) { Add-ValidationError "$configName contains an invalid percentage." }
            if ([string]$preset.mode -eq "fit" -and [int]$preset.value -lt 1) { Add-ValidationError "$configName contains an invalid pixel size." }
            if ([string]$preset.operation -eq "copy" -and [string]::IsNullOrWhiteSpace([string]$preset.copySuffix)) { Add-ValidationError "$configName contains a copy preset without a suffix." }
        }
    }
    catch {
        Add-ValidationError "$configName is invalid: $($_.Exception.Message)"
    }
}

$imageMagickFiles = @("magick.exe", "LICENSE.txt", "NOTICE.txt")
foreach ($fileName in $imageMagickFiles) {
    $relativePath = "ImageMagick\$fileName"
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $relativePath) -PathType Leaf)) {
        if ($RequireImageMagick) { Add-ValidationError "Missing bundled runtime file: $relativePath" }
        else { $warnings.Add("Missing bundled runtime file: $relativePath") }
    }
}

if ($RequireImageMagick -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot "ImageMagick\magick.exe") -PathType Leaf)) {
    try {
        $versionOutput = @(& (Join-Path $PSScriptRoot "ImageMagick\magick.exe") -version 2>&1)
        if ($LASTEXITCODE -ne 0 -or ($versionOutput -join " ") -notmatch "ImageMagick") {
            Add-ValidationError "The bundled magick.exe did not return a valid version."
        }
    }
    catch {
        Add-ValidationError "The bundled magick.exe could not be executed: $($_.Exception.Message)"
    }
}

$version = ""
try { $version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "VERSION.txt") -Raw).Trim() }
catch { Add-ValidationError "VERSION.txt could not be read." }
if ($version -notmatch "^\d+\.\d+\.\d+$") { Add-ValidationError "VERSION.txt must contain a semantic version such as 1.0.0." }

foreach ($warning in $warnings) { Write-Host "WARNING: $warning" -ForegroundColor Yellow }
foreach ($validationError in $errors) { Write-Host "ERROR: $validationError" -ForegroundColor Red }

if ($errors.Count -gt 0) {
    Write-Host "Validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "Project validation passed." -ForegroundColor Green
if ($warnings.Count -gt 0) { Write-Host "The source tree is valid, but the runtime package is incomplete." -ForegroundColor Yellow }
exit 0
