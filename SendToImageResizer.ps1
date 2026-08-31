[CmdletBinding()]
param(
    [string]$PresetName,
    [string]$MainFolder,
    [switch]$AllowReplace,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$InputPaths
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:AppName = "SendToImageResizer"
$script:ConfigPath = Join-Path $PSScriptRoot "presets.json"
$script:DefaultConfigPath = Join-Path $PSScriptRoot "presets.default.json"
$script:MagickPath = Join-Path $PSScriptRoot "ImageMagick\magick.exe"

function Write-Title {
    Clear-Host
    Write-Host "========================================" -ForegroundColor DarkCyan
    Write-Host "  SendToImageResizer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor DarkCyan
    Write-Host
}

function Pause-Menu {
    Write-Host
    [void](Read-Host "Press Enter to continue")
}

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

    try {
        $config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "presets.json is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $config -or $config.PSObject.Properties.Name -notcontains "presets") {
        throw "presets.json does not contain a presets array."
    }

    if ($config.PSObject.Properties.Name -notcontains "supportedExtensions") {
        throw "presets.json does not contain supportedExtensions."
    }

    $presets = @($config.presets)
    if ($presets.Count -eq 0) {
        throw "presets.json does not contain any presets."
    }

    foreach ($preset in $presets) {
        Assert-Preset -Preset $preset
    }

    return $config
}

function Save-Config {
    param([Parameter(Mandatory = $true)]$Config)

    $json = $Config | ConvertTo-Json -Depth 10
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:ConfigPath, $json + [Environment]::NewLine, $utf8WithoutBom)
}

function Assert-Preset {
    param([Parameter(Mandatory = $true)]$Preset)

    $name = [string](Get-PropertyValue -Object $Preset -Name "name" -Default "")
    $mode = ([string](Get-PropertyValue -Object $Preset -Name "mode" -Default "")).ToLowerInvariant()
    $operation = ([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "")).ToLowerInvariant()
    $quality = [int](Get-PropertyValue -Object $Preset -Name "quality" -Default 0)
    $value = [int](Get-PropertyValue -Object $Preset -Name "value" -Default 0)

    if ([string]::IsNullOrWhiteSpace($name)) { throw "A preset has no name." }
    if ($mode -notin @("none", "percent", "fit")) { throw "Preset '$name' has an invalid mode." }
    if ($operation -notin @("copy", "replace")) { throw "Preset '$name' has an invalid operation." }
    if ($quality -lt 1 -or $quality -gt 100) { throw "Preset '$name' has an invalid quality." }
    if ($mode -eq "percent" -and ($value -lt 1 -or $value -gt 100)) {
        throw "Preset '$name' must use a percentage between 1 and 100."
    }
    if ($mode -eq "fit" -and $value -lt 1) { throw "Preset '$name' must use a positive pixel size." }

    if ($operation -eq "copy") {
        $suffix = [string](Get-PropertyValue -Object $Preset -Name "copySuffix" -Default "")
        if ([string]::IsNullOrWhiteSpace($suffix)) { throw "Preset '$name' needs a copySuffix." }
        if ($suffix.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "Preset '$name' has an invalid copySuffix."
        }
    }
}

function Select-MainFolder {
    param([string]$InitialDirectory)

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the main folder containing the images"
    $dialog.ShowNewFolderButton = $false
    if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
        $dialog.SelectedPath = $InitialDirectory
    }

    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
    }
    finally {
        $dialog.Dispose()
    }

    return $null
}

function Resolve-InitialFolder {
    param([string[]]$Paths)

    $validItems = @()
    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path)) {
            $validItems += Get-Item -LiteralPath $path
        }
    }

    if ($validItems.Count -eq 1 -and $validItems[0].PSIsContainer) {
        return $validItems[0].FullName
    }

    if ($validItems.Count -gt 0) {
        $folders = @($validItems | ForEach-Object {
            if ($_.PSIsContainer) { $_.FullName } else { $_.DirectoryName }
        } | Select-Object -Unique)

        if ($folders.Count -eq 1) {
            Write-Host "Individual files were passed. Using their parent folder instead:" -ForegroundColor Yellow
            Write-Host $folders[0]
            Write-Host "For large batches, send the main folder to Image Resizer." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            return $folders[0]
        }
    }

    return Select-MainFolder
}

function Get-ImageFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Preset
    )

    $extensions = @($Config.supportedExtensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $recursive = [bool](Get-PropertyValue -Object $Preset -Name "recursive" -Default $false)
    $parameters = @{
        LiteralPath = $Folder
        File = $true
        ErrorAction = "SilentlyContinue"
    }
    if ($recursive) { $parameters.Recurse = $true }

    $files = @(Get-ChildItem @parameters | Where-Object {
        ($extensions -contains $_.Extension.ToLowerInvariant()) -and
        (-not $_.BaseName.StartsWith(".stir-", [StringComparison]::OrdinalIgnoreCase))
    })

    if (([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "copy")) -eq "copy") {
        $suffix = [string](Get-PropertyValue -Object $Preset -Name "copySuffix" -Default "_resized")
        $files = @($files | Where-Object { -not $_.BaseName.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) })
    }

    return @($files | Sort-Object FullName)
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
        "percent" {
            $arguments += "-resize"
            $arguments += ("{0}%" -f $value)
        }
        "fit" {
            $arguments += "-resize"
            $arguments += ("{0}x{0}>" -f $value)
        }
    }
    $arguments += "-quality"
    $arguments += [string]$quality
    $arguments += $tempPath

    $backupPath = $null
    try {
        $magickOutput = @(& $script:MagickPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            $details = ($magickOutput | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($details)) { $details = "ImageMagick exit code: $exitCode" }
            throw $details
        }

        $tempItem = Get-Item -LiteralPath $tempPath
        if ($tempItem.Length -le 0) { throw "ImageMagick created an empty file." }

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

function Invoke-Preset {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)]$Preset,
        [switch]$NonInteractive,
        [switch]$AllowReplace
    )

    if (-not (Test-Path -LiteralPath $script:MagickPath -PathType Leaf)) {
        if ($NonInteractive) { throw "ImageMagick is incomplete. Missing: $script:MagickPath" }
        Write-Host "ImageMagick is incomplete." -ForegroundColor Red
        Write-Host "Missing: $script:MagickPath"
        Write-Host "Run Install.cmd again from a complete release package."
        Pause-Menu
        return $false
    }

    $files = @(Get-ImageFiles -Folder $Folder -Config $Config -Preset $Preset)
    if ($files.Count -eq 0) {
        if ($NonInteractive) { throw "No supported images were found." }
        Write-Host "No supported images were found." -ForegroundColor Yellow
        Pause-Menu
        return $false
    }

    $operation = ([string](Get-PropertyValue -Object $Preset -Name "operation" -Default "copy")).ToLowerInvariant()
    Write-Host
    Write-Host ("Preset : {0}" -f $Preset.name)
    Write-Host ("Images : {0}" -f $files.Count)
    Write-Host ("Output : {0}" -f $(if ($operation -eq "replace") { "Replace originals" } else { "Create copies" }))

    if ($operation -eq "replace") {
        if ($NonInteractive -and -not $AllowReplace) {
            throw "A non-interactive replace operation requires -AllowReplace."
        }
        Write-Host
        Write-Host "This preset replaces the original files." -ForegroundColor Yellow
        if (-not $NonInteractive) {
            $confirmation = Read-Host "Type YES to continue"
            if ($confirmation -cne "YES") { return $false }
        }
    }

    $success = 0
    $skipped = 0
    $failed = 0
    [long]$bytesBefore = 0
    [long]$bytesAfter = 0
    $failures = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        $percent = [int](($index / [Math]::Max($files.Count, 1)) * 100)
        Write-Progress -Activity "Processing images" -Status ("{0} of {1}: {2}" -f ($index + 1), $files.Count, $file.Name) -PercentComplete $percent
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
                $failures.Add([pscustomobject]@{ File = $file.FullName; Error = $result.Message })
            }
        }
    }
    Write-Progress -Activity "Processing images" -Completed

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

    if (-not $NonInteractive) { Pause-Menu }
    return ($failed -eq 0)
}

function Read-TextValue {
    param([string]$Label, [string]$Current)
    $value = Read-Host ("{0} [{1}]" -f $Label, $Current)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Current }
    return $value.Trim()
}

function Read-IntegerValue {
    param([string]$Label, [int]$Current, [int]$Minimum, [int]$Maximum)
    while ($true) {
        $raw = Read-Host ("{0} [{1}]" -f $Label, $Current)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Current }
        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge $Minimum -and $parsed -le $Maximum) {
            return $parsed
        }
        Write-Host ("Enter a number between {0} and {1}." -f $Minimum, $Maximum) -ForegroundColor Yellow
    }
}

function Read-BooleanValue {
    param([string]$Label, [bool]$Current)
    $defaultLabel = $(if ($Current) { "Y" } else { "N" })
    while ($true) {
        $raw = (Read-Host ("{0} (Y/N) [{1}]" -f $Label, $defaultLabel)).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Current }
        if ($raw -match "^(y|yes)$") { return $true }
        if ($raw -match "^(n|no)$") { return $false }
        Write-Host "Enter Y or N." -ForegroundColor Yellow
    }
}

function Read-EnumValue {
    param([string]$Label, [string]$Current, [string[]]$Allowed)
    while ($true) {
        $raw = (Read-Host ("{0} ({1}) [{2}]" -f $Label, ($Allowed -join "/"), $Current)).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Current }
        if ($Allowed -contains $raw) { return $raw }
        Write-Host ("Choose one of: {0}" -f ($Allowed -join ", ")) -ForegroundColor Yellow
    }
}

function Read-PresetDefinition {
    param($CurrentPreset)

    if ($null -eq $CurrentPreset) {
        $CurrentPreset = [pscustomobject][ordered]@{
            name = "New preset"
            mode = "fit"
            value = 1920
            quality = 80
            autoOrient = $false
            operation = "copy"
            copySuffix = "_resized"
            overwriteCopy = $false
            recursive = $true
            preserveTimestamps = $true
        }
    }

    Write-Host
    $name = Read-TextValue -Label "Name" -Current ([string]$CurrentPreset.name)
    $mode = Read-EnumValue -Label "Resize mode" -Current ([string]$CurrentPreset.mode) -Allowed @("none", "percent", "fit")
    $value = [int](Get-PropertyValue -Object $CurrentPreset -Name "value" -Default 0)
    if ($mode -eq "percent") { $value = Read-IntegerValue -Label "Percentage" -Current $(if ($value -ge 1 -and $value -le 100) { $value } else { 50 }) -Minimum 1 -Maximum 100 }
    if ($mode -eq "fit") { $value = Read-IntegerValue -Label "Maximum edge in pixels" -Current $(if ($value -gt 0) { $value } else { 1920 }) -Minimum 1 -Maximum 100000 }
    if ($mode -eq "none") { $value = 0 }
    $quality = Read-IntegerValue -Label "Quality" -Current ([int]$CurrentPreset.quality) -Minimum 1 -Maximum 100
    $autoOrient = Read-BooleanValue -Label "Auto orient" -Current ([bool](Get-PropertyValue -Object $CurrentPreset -Name "autoOrient" -Default $false))
    $operation = Read-EnumValue -Label "Output" -Current ([string](Get-PropertyValue -Object $CurrentPreset -Name "operation" -Default "copy")) -Allowed @("copy", "replace")
    $copySuffix = [string](Get-PropertyValue -Object $CurrentPreset -Name "copySuffix" -Default "_resized")
    $overwriteCopy = [bool](Get-PropertyValue -Object $CurrentPreset -Name "overwriteCopy" -Default $false)
    if ($operation -eq "copy") {
        do {
            $copySuffix = Read-TextValue -Label "Copy suffix" -Current $copySuffix
            $suffixValid = -not [string]::IsNullOrWhiteSpace($copySuffix) -and $copySuffix.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0
            if (-not $suffixValid) { Write-Host "The suffix is not valid for a file name." -ForegroundColor Yellow }
        } while (-not $suffixValid)
        $overwriteCopy = Read-BooleanValue -Label "Overwrite an existing copy" -Current $overwriteCopy
    }
    $recursive = Read-BooleanValue -Label "Include subfolders" -Current ([bool](Get-PropertyValue -Object $CurrentPreset -Name "recursive" -Default $true))
    $preserveTimestamps = Read-BooleanValue -Label "Preserve timestamps" -Current ([bool](Get-PropertyValue -Object $CurrentPreset -Name "preserveTimestamps" -Default $true))

    $result = [pscustomobject][ordered]@{
        name = $name
        mode = $mode
        value = $value
        quality = $quality
        autoOrient = $autoOrient
        operation = $operation
        copySuffix = $copySuffix
        overwriteCopy = $overwriteCopy
        recursive = $recursive
        preserveTimestamps = $preserveTimestamps
    }
    Assert-Preset -Preset $result
    return $result
}

function Read-PresetNumber {
    param([object[]]$Presets, [string]$Prompt)
    $raw = Read-Host $Prompt
    $number = 0
    if (-not [int]::TryParse($raw, [ref]$number) -or $number -lt 1 -or $number -gt $Presets.Count) {
        return -1
    }
    return ($number - 1)
}

function Edit-Presets {
    while ($true) {
        Write-Title
        try { $config = Read-Config }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host
            Write-Host "O - Open presets.json"
            Write-Host "R - Reset defaults"
            Write-Host "B - Back"
            $invalidChoice = (Read-Host "Select").Trim().ToUpperInvariant()
            if ($invalidChoice -eq "O") { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath) -Wait }
            elseif ($invalidChoice -eq "R" -and (Test-Path -LiteralPath $script:DefaultConfigPath)) { Copy-Item $script:DefaultConfigPath $script:ConfigPath -Force }
            elseif ($invalidChoice -eq "B") { return }
            continue
        }

        $presets = @($config.presets)
        Write-Host "Preset editor" -ForegroundColor Cyan
        Write-Host
        for ($index = 0; $index -lt $presets.Count; $index++) {
            Write-Host ("{0,2} - {1}" -f ($index + 1), $presets[$index].name)
        }
        Write-Host
        Write-Host "N - New preset"
        Write-Host "E - Edit preset"
        Write-Host "D - Delete preset"
        Write-Host "O - Open presets.json in Notepad"
        Write-Host "R - Reset defaults"
        Write-Host "B - Back"
        Write-Host
        $choice = (Read-Host "Select").Trim().ToUpperInvariant()

        switch ($choice) {
            "N" {
                $newPreset = Read-PresetDefinition -CurrentPreset $null
                $config.presets = @($presets) + @($newPreset)
                Save-Config -Config $config
            }
            "E" {
                $selected = Read-PresetNumber -Presets $presets -Prompt "Preset number"
                if ($selected -ge 0) {
                    $presets[$selected] = Read-PresetDefinition -CurrentPreset $presets[$selected]
                    $config.presets = @($presets)
                    Save-Config -Config $config
                }
            }
            "D" {
                if ($presets.Count -le 1) {
                    Write-Host "At least one preset must remain." -ForegroundColor Yellow
                    Pause-Menu
                    continue
                }
                $selected = Read-PresetNumber -Presets $presets -Prompt "Preset number"
                if ($selected -ge 0) {
                    $confirmDelete = Read-Host ("Delete '{0}'? (Y/N)" -f $presets[$selected].name)
                    if ($confirmDelete -match "^(y|yes)$") {
                        $newPresets = @()
                        for ($index = 0; $index -lt $presets.Count; $index++) {
                            if ($index -ne $selected) { $newPresets += $presets[$index] }
                        }
                        $config.presets = @($newPresets)
                        Save-Config -Config $config
                    }
                }
            }
            "O" { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:ConfigPath) -Wait }
            "R" {
                $confirmReset = Read-Host "Reset all presets to defaults? (Y/N)"
                if ($confirmReset -match "^(y|yes)$") {
                    Copy-Item -LiteralPath $script:DefaultConfigPath -Destination $script:ConfigPath -Force
                }
            }
            "B" { return }
        }
    }
}

function Show-MainMenu {
    $folder = Resolve-InitialFolder -Paths $InputPaths

    while ($true) {
        Write-Title
        Write-Host "Main folder:" -ForegroundColor DarkCyan
        if ([string]::IsNullOrWhiteSpace($folder)) {
            Write-Host "Not selected" -ForegroundColor Yellow
        }
        else {
            Write-Host $folder
        }
        Write-Host

        try { $config = Read-Config }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host "Use E to repair or reset the presets."
            $config = $null
        }

        if ($null -ne $config) {
            $presets = @($config.presets)
            for ($index = 0; $index -lt $presets.Count; $index++) {
                $preset = $presets[$index]
                $operationLabel = $(if ($preset.operation -eq "replace") { "replace" } else { "copy" })
                Write-Host ("{0,2} - {1} [{2}]" -f ($index + 1), $preset.name, $operationLabel)
            }
        }
        else {
            $presets = @()
        }

        Write-Host
        Write-Host "F - Select main folder"
        Write-Host "E - Edit presets"
        Write-Host "Q - Quit"
        Write-Host
        $choice = (Read-Host "Select").Trim().TrimStart([char]0xFEFF)

        if ($choice -match "^[fF]$") {
            $selectedFolder = Select-MainFolder -InitialDirectory $folder
            if ($null -ne $selectedFolder) { $folder = $selectedFolder }
            continue
        }
        if ($choice -match "^[eE]$") { Edit-Presets; continue }
        if ($choice -match "^[qQ]$") { return }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $presets.Count) {
            if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Host "Select a main folder first." -ForegroundColor Yellow
                Pause-Menu
                continue
            }
            [void](Invoke-Preset -Folder $folder -Config $config -Preset $presets[$number - 1])
        }
    }
}

try {
    if (-not [string]::IsNullOrWhiteSpace($PresetName)) {
        if ([string]::IsNullOrWhiteSpace($MainFolder) -or -not (Test-Path -LiteralPath $MainFolder -PathType Container)) {
            throw "-MainFolder must point to an existing folder."
        }
        $config = Read-Config
        $matchingPresets = @($config.presets | Where-Object { $_.name -eq $PresetName })
        if ($matchingPresets.Count -ne 1) {
            throw "Preset '$PresetName' was not found or is not unique."
        }
        $completed = Invoke-Preset -Folder $MainFolder -Config $config -Preset $matchingPresets[0] -NonInteractive -AllowReplace:$AllowReplace
        if ($completed) { exit 0 } else { exit 1 }
    }
    else {
        Show-MainMenu
        exit 0
    }
}
catch {
    Write-Host
    Write-Host "Fatal error:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host
    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        [void](Read-Host "Press Enter to close")
    }
    exit 1
}
