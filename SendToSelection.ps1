[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputPaths
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:MainScript = Join-Path $PSScriptRoot "SendToImageResizer.ps1"
$script:ConfigPath = Join-Path $PSScriptRoot "presets.json"
$script:DefaultConfigPath = Join-Path $PSScriptRoot "presets.default.json"
$script:MagickPath = Join-Path $PSScriptRoot "ImageMagick\magick.exe"

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default
    )

    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $script:DefaultConfigPath -PathType Leaf)) {
            throw "Neither presets.json nor presets.default.json was found."
        }
        Copy-Item -LiteralPath $script:DefaultConfigPath -Destination $script:ConfigPath -Force
    }

    $config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config -or $config.PSObject.Properties.Name -notcontains "presets") {
        throw "presets.json does not contain a presets array."
    }
    return $config
}

function Get-SelectedImageFiles {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Preset
    )

    $extensions = @($Config.supportedExtensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $path
        if ($extensions -notcontains $item.Extension.ToLowerInvariant()) { continue }
        if ($item.BaseName.StartsWith(".stir-", [StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$files.Add($item)
    }

    if (([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "copy")) -eq "copy") {
        $suffix = [string](Get-PropertyValue -Object $Preset -Name "copySuffix" -Default "_resized")
        $files = @($files | Where-Object { -not $_.BaseName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) })
    }

    return @($files | Sort-Object FullName -Unique)
}

function Set-FileTimestamps {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Timestamps
    )

    $item = Get-Item -LiteralPath $Path
    $item.CreationTime = $Timestamps.CreationTime
    $item.LastWriteTime = $Timestamps.LastWriteTime
    $item.LastAccessTime = $Timestamps.LastAccessTime
}

function Move-ToRecycleBin {
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
        $Path,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
}

function Invoke-ImageResize {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)]$Preset
    )

    $mode = ([string](Get-PropertyValue -Object $Preset -Name "mode" -Default "none")).ToLowerInvariant()
    $operation = ([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "copy")).ToLowerInvariant()
    $quality = [int](Get-PropertyValue -Object $Preset -Name "quality" -Default 80)
    $value = [int](Get-PropertyValue -Object $Preset -Name "value" -Default 0)
    $autoOrient = [bool](Get-PropertyValue -Object $Preset -Name "autoOrient" -Default $false)
    $preserveTimestamps = [bool](Get-PropertyValue -Object $Preset -Name "preserveTimestamps" -Default $true)
    $timestamps = [pscustomobject]@{
        CreationTime = $File.CreationTime
        LastWriteTime = $File.LastWriteTime
        LastAccessTime = $File.LastAccessTime
    }

    $tempPath = Join-Path $File.DirectoryName (".stir-{0}{1}" -f [Guid]::NewGuid().ToString("N"), $File.Extension)
    $outputPath = $File.FullName

    if ($operation -eq "copy") {
        $suffix = [string](Get-PropertyValue -Object $Preset -Name "copySuffix" -Default "_resized")
        $outputPath = Join-Path $File.DirectoryName ($File.BaseName + $suffix + $File.Extension)
        $overwriteCopy = [bool](Get-PropertyValue -Object $Preset -Name "overwriteCopy" -Default $false)
        if ((Test-Path -LiteralPath $outputPath) -and -not $overwriteCopy) {
            return [pscustomobject]@{ Status = "Skipped"; Message = "Copy already exists"; OutputPath = $outputPath; BytesBefore = $File.Length; BytesAfter = 0 }
        }
    }

    $arguments = @($File.FullName)
    if ($autoOrient) { $arguments += "-auto-orient" }
    switch ($mode) {
        "percent" { $arguments += @("-resize", ("{0}%" -f $value)) }
        "fit" { $arguments += @("-resize", ("{0}x{0}>" -f $value)) }
    }
    $arguments += @("-quality", [string]$quality, $tempPath)

    $backupPath = $null
    try {
        $magickOutput = @(& $script:MagickPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            $details = ($magickOutput | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($details)) { $details = "ImageMagick exit code: $exitCode" }
            throw $details
        }

        if ((Get-Item -LiteralPath $tempPath).Length -le 0) { throw "ImageMagick created an empty file." }

        if ($operation -eq "copy") {
            Move-Item -LiteralPath $tempPath -Destination $outputPath -Force
            if ($preserveTimestamps) { Set-FileTimestamps -Path $outputPath -Timestamps $timestamps }
        }
        else {
            $backupPath = Join-Path $File.DirectoryName (".stir-backup-{0}{1}" -f [Guid]::NewGuid().ToString("N"), $File.Extension)
            Move-Item -LiteralPath $File.FullName -Destination $backupPath
            try {
                Move-Item -LiteralPath $tempPath -Destination $File.FullName
                if ($preserveTimestamps) { Set-FileTimestamps -Path $File.FullName -Timestamps $timestamps }
            }
            catch {
                if (Test-Path -LiteralPath $File.FullName) { Remove-Item -LiteralPath $File.FullName -Force }
                Move-Item -LiteralPath $backupPath -Destination $File.FullName
                throw
            }

            try {
                Move-ToRecycleBin -Path $backupPath
                $backupPath = $null
            }
            catch {
                Write-Warning "The original was kept as a backup: $backupPath"
            }
            $outputPath = $File.FullName
        }

        $outputItem = Get-Item -LiteralPath $outputPath
        return [pscustomobject]@{
            Status = "Success"
            Message = "OK"
            OutputPath = $outputPath
            BytesBefore = $File.Length
            BytesAfter = $outputItem.Length
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $File.FullName)) {
            Move-Item -LiteralPath $backupPath -Destination $File.FullName -ErrorAction SilentlyContinue
        }
        return [pscustomobject]@{
            Status = "Failed"
            Message = $_.Exception.Message
            OutputPath = $File.FullName
            BytesBefore = $File.Length
            BytesAfter = 0
        }
    }
}

function Invoke-SelectedFiles {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo[]]$Files,
        [Parameter(Mandatory = $true)]$Preset
    )

    if (-not (Test-Path -LiteralPath $script:MagickPath -PathType Leaf)) {
        throw "ImageMagick is incomplete. Missing: $script:MagickPath"
    }

    $operation = ([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "copy")).ToLowerInvariant()
    Write-Host
    Write-Host ("Preset : {0}" -f $Preset.name)
    Write-Host ("Images : {0}" -f $Files.Count)
    Write-Host ("Output : {0}" -f $(if ($operation -eq "replace") { "Replace originals" } else { "Create copies" }))

    $success = 0
    $skipped = 0
    $failed = 0
    [long]$bytesBefore = 0
    [long]$bytesAfter = 0
    $failures = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $Files.Count; $index++) {
        $file = $Files[$index]
        $percent = [int](($index / [Math]::Max($Files.Count, 1)) * 100)
        Write-Progress -Activity "Processing selected images" -Status ("{0} of {1}: {2}" -f ($index + 1), $Files.Count, $file.Name) -PercentComplete $percent
        $result = Invoke-ImageResize -File $file -Preset $Preset

        switch ($result.Status) {
            "Success" {
                $success++
                $bytesBefore += $result.BytesBefore
                $bytesAfter += $result.BytesAfter
            }
            "Skipped" { $skipped++ }
            default {
                $failed++
                [void]$failures.Add([pscustomobject]@{ File = $file.FullName; Error = $result.Message })
            }
        }
    }
    Write-Progress -Activity "Processing selected images" -Completed

    Write-Host
    Write-Host "Completed" -ForegroundColor Green
    Write-Host ("Successful : {0}" -f $success)
    Write-Host ("Skipped    : {0}" -f $skipped)
    Write-Host ("Failed     : {0}" -f $failed)
    if ($success -gt 0 -and $bytesBefore -gt 0) {
        $change = [Math]::Round((1 - ($bytesAfter / [double]$bytesBefore)) * 100, 1)
        Write-Host ("Size change: {0}%" -f $change)
    }

    if ($failures.Count -gt 0) {
        Write-Host
        Write-Host "Errors:" -ForegroundColor Red
        foreach ($failure in $failures) {
            Write-Host ("- {0}" -f $failure.File)
            Write-Host ("  {0}" -f $failure.Error) -ForegroundColor DarkRed
        }
    }

    Write-Host
    [void](Read-Host "Press Enter to close")
}

try {
    $validItems = @($InputPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } | ForEach-Object { Get-Item -LiteralPath $_ })

    if ($validItems.Count -eq 0) {
        & $script:MainScript
        exit $LASTEXITCODE
    }

    if ($validItems.Count -eq 1 -and $validItems[0].PSIsContainer) {
        & $script:MainScript $validItems[0].FullName
        exit $LASTEXITCODE
    }

    $filePaths = @($validItems | Where-Object { -not $_.PSIsContainer } | ForEach-Object { $_.FullName })
    if ($filePaths.Count -eq 0) {
        throw "Select one folder or one or more image files."
    }

    while ($true) {
        Clear-Host
        Write-Host "========================================" -ForegroundColor DarkCyan
        Write-Host "  SendToImageResizer" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor DarkCyan
        Write-Host
        Write-Host ("Selected files: {0}" -f $filePaths.Count) -ForegroundColor DarkCyan
        Write-Host

        $config = Read-Config
        $presets = @($config.presets)
        for ($index = 0; $index -lt $presets.Count; $index++) {
            $operationLabel = $(if ($presets[$index].operation -eq "replace") { "replace" } else { "copy" })
            Write-Host ("{0,2} - {1} [{2}]" -f ($index + 1), $presets[$index].name, $operationLabel)
        }
        Write-Host
        Write-Host "C - Open preset configuration"
        Write-Host "Q - Quit"
        Write-Host
        $choice = (Read-Host "Select").Trim().TrimStart([char]0xFEFF)

        if ($choice -match "^[qQ]$") { exit 0 }
        if ($choice -match "^[cC]$") {
            Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath) -Wait
            continue
        }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $presets.Count) { continue }

        $preset = $presets[$number - 1]
        $files = @(Get-SelectedImageFiles -Paths $filePaths -Config $config -Preset $preset)
        if ($files.Count -eq 0) {
            Write-Host "No supported selected images were found." -ForegroundColor Yellow
            Write-Host
            [void](Read-Host "Press Enter to close")
            exit 1
        }

        Invoke-SelectedFiles -Files $files -Preset $preset
        exit 0
    }
}
catch {
    Write-Host
    Write-Host "Fatal error:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host
    [void](Read-Host "Press Enter to close")
    exit 1
}
