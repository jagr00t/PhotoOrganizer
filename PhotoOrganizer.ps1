<#
.SYNOPSIS
  Safely renames media in one folder in capture-time order and can remove metadata.

.DESCRIPTION
  Date priority is DateTimeOriginal, CreateDate, LastWriteTimeUtc, then
  CreationTimeUtc.  The script only processes supported files that do not already
  use this folder's generated name.  It calls ExifTool once to read dates and once
  (after successful renames) to remove writable metadata.

.EXAMPLE
  # Preview the current folder (the default configured behaviour)
  .\PhotoOrganizer.ps1

.EXAMPLE
  # Apply changes to a media folder after reviewing a preview
  .\PhotoOrganizer.ps1 -TargetPath 'D:\Photos\Japan Trip' -Force

.EXAMPLE
  # Explicit preview; no files or metadata are changed
  .\PhotoOrganizer.ps1 -TargetPath 'D:\Photos\Japan Trip' -DryRun
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$TargetPath = (Get-Location).Path,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoMetadata
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-RunLog {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO')
    $line = '{0:u} [{1}] {2}' -f (Get-Date), $Level, $Message
    Write-Host $line
    Add-Content -LiteralPath $script:RunLogPath -Value $line -Encoding utf8
}

function Get-SafePrefix {
    param([string]$Name)
    $invalid = [Regex]::Escape((-join [IO.Path]::GetInvalidFileNameChars()))
    $safe = [Regex]::Replace($Name, "[$invalid]", ' ')
    $safe = [Regex]::Replace($safe, '\s+', ' ').Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'Media' }
    return $safe
}

function Convert-ExifDateToUtc {
    param([object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    # ExifTool's common EXIF form is yyyy:MM:dd HH:mm:ss. Time-zone offsets, when
    # present, are parsed separately; otherwise the camera time is treated as local.
    $text = ([string]$Value).Trim()
    $formats = @('yyyy:MM:dd HH:mm:ssK', 'yyyy:MM:dd HH:mm:ss', 'yyyy-MM-dd HH:mm:ssK', 'yyyy-MM-dd HH:mm:ss')
    $result = [datetime]::MinValue
    foreach ($format in $formats) {
        if ([datetime]::TryParseExact($text, $format, [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$result)) {
            if ($text -match '(Z|[+-]\d\d:?\d\d)$') { return $result.ToUniversalTime() }
            return [datetime]::SpecifyKind($result, [DateTimeKind]::Local).ToUniversalTime()
        }
    }
    return $null
}

function Get-ExifTool {
    $command = Get-Command exiftool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw 'ExifTool was not found in PATH. Install ExifTool, add its folder to PATH, then open a new PowerShell window.'
    }
    return $command.Source
}

function Get-ImageMagick {
    $command = Get-Command magick -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw 'ImageMagick was not found in PATH. Orientation baking is enabled, so no files were changed. Install ImageMagick (the magick command), add it to PATH, then open a new PowerShell window; or set BakeOrientation to false in PhotoOrganizer.json.'
    }
    return $command.Source
}

function Invoke-ExifToolJson {
    param([string]$ExifToolPath, [object[]]$Files, [string]$WorkingDirectory)
    if ($Files.Count -eq 0) { return @() }
    $listPath = Join-Path $WorkingDirectory ('PhotoOrganizer-input-{0}.txt' -f [guid]::NewGuid())
    $errorPath = Join-Path $WorkingDirectory ('PhotoOrganizer-exif-errors-{0}.txt' -f [guid]::NewGuid())
    try {
        [IO.File]::WriteAllLines($listPath, [string[]]($Files | ForEach-Object FullName), [Text.UTF8Encoding]::new($false))
        # Keep ExifTool diagnostics on stderr out of the JSON response. Some media
        # formats emit warnings; merging stderr with stdout makes ConvertFrom-Json fail.
        $raw = & $ExifToolPath -j -DateTimeOriginal -CreateDate -charset filename=UTF8 '-@' $listPath 2> $errorPath
        $diagnostics = if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw } else { '' }
        if ($LASTEXITCODE -ne 0) { throw "ExifTool date read failed: $diagnostics" }
        $json = $raw -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        try { return @($json | ConvertFrom-Json) }
        catch { throw "ExifTool returned invalid JSON. Diagnostics: $diagnostics`n$($_.Exception.Message)" }
    }
    finally {
        Remove-Item -LiteralPath $listPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-DateIndex {
    param([object[]]$ExifRecords)
    $index = @{}
    foreach ($record in $ExifRecords) { if ($record.SourceFile) { $index[$record.SourceFile] = $record } }
    return $index
}

try {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $configPath = Join-Path $scriptRoot 'PhotoOrganizer.json'
    if (-not (Test-Path -LiteralPath $configPath)) { throw "Configuration file is missing: $configPath" }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $TargetPath = (Resolve-Path -LiteralPath $TargetPath).Path
    $prefix = Get-SafePrefix (Split-Path -Leaf $TargetPath)
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $logDirectory = Join-Path $TargetPath 'PhotoOrganizer-Logs'
    if (-not (Test-Path -LiteralPath $logDirectory)) { New-Item -ItemType Directory -Path $logDirectory | Out-Null }
    $script:RunLogPath = Join-Path $logDirectory "Run_$timestamp.txt"
    New-Item -ItemType File -Path $script:RunLogPath -Force | Out-Null
    $undoPath = Join-Path $logDirectory "Undo_$timestamp.csv"

    $isDryRun = [bool]$config.DryRun -or $DryRun.IsPresent
    $removeMetadata = [bool]$config.RemoveMetadata -and -not $NoMetadata.IsPresent
    $bakeOrientation = [bool]$config.BakeOrientation
    $minimumPadding = [Math]::Max(1, [int]$config.MinimumPadding)
    $extensions = @($config.SupportedExtensions | ForEach-Object { $_.ToLowerInvariant() })
    # These are the raster image formats normalized by ImageMagick. RAW files and
    # videos are deliberately excluded: they are not safely pixel-rotated here.
    $orientationExtensions = @('.jpg', '.jpeg', '.png', '.webp', '.tif', '.tiff', '.heic', '.heif')
    $escapedPrefix = [regex]::Escape($prefix)
    $renamedPattern = "^${escapedPrefix}_(\d+)$"
    Write-RunLog "PhotoOrganizer v1.0 started. Folder='$TargetPath'; prefix='$prefix'; dry-run=$isDryRun."

    $exifTool = Get-ExifTool
    Write-RunLog "Using ExifTool: $exifTool"
    $allFiles = @(Get-ChildItem -LiteralPath $TargetPath -File -Force | Where-Object {
        $extensions -contains $_.Extension.ToLowerInvariant()
    })
    $existingNumbers = @($allFiles | ForEach-Object {
        $match = [regex]::Match($_.BaseName, $renamedPattern)
        if ($match.Success) { [int]$match.Groups[1].Value }
    })
    # Measure-Object can return a floating-point Maximum; sequence formatting needs
    # an integer (the D format specifier is invalid for a floating-point value).
    $highestExisting = if ($existingNumbers.Count) { [Int64](($existingNumbers | Measure-Object -Maximum).Maximum) } else { [Int64]0 }
    $candidates = @($allFiles | Where-Object { $_.BaseName -notmatch $renamedPattern })
    $skipped = $allFiles.Count - $candidates.Count
    if ($candidates.Count -eq 0) {
        Write-RunLog "No new supported media files found. Skipped already named files: $skipped."
        return
    }

    # Do this preflight before any rename. It prevents a later metadata-removal
    # step from deleting Orientation tags when pixel normalization is unavailable.
    $imageMagick = $null
    if (-not $isDryRun -and $removeMetadata -and $bakeOrientation -and @($candidates | Where-Object { $orientationExtensions -contains $_.Extension.ToLowerInvariant() }).Count) {
        $imageMagick = Get-ImageMagick
        Write-RunLog "Using ImageMagick for orientation normalization: $imageMagick"
    }

    Write-RunLog "Reading capture dates once for $($candidates.Count) candidate file(s)."
    $dateIndex = Get-DateIndex (Invoke-ExifToolJson -ExifToolPath $exifTool -Files $candidates -WorkingDirectory $logDirectory)
    $datedFiles = foreach ($file in $candidates) {
        $record = $dateIndex[$file.FullName]
        $date = if ($record) { Convert-ExifDateToUtc $record.DateTimeOriginal } else { $null }
        $source = 'DateTimeOriginal'
        if (-not $date) { $date = if ($record) { Convert-ExifDateToUtc $record.CreateDate } else { $null }; $source = 'CreateDate' }
        if (-not $date) { $date = $file.LastWriteTimeUtc; $source = 'LastWriteTimeUtc' }
        if (-not $date) { $date = $file.CreationTimeUtc; $source = 'CreationTimeUtc' }
        [pscustomobject]@{ File=$file; SortDate=$date; DateSource=$source }
    }
    $ordered = @($datedFiles | Sort-Object SortDate, @{ Expression = { $_.File.Name }; Ascending = $true })
    $lastNumber = $highestExisting + $ordered.Count
    $existingWidth = @($allFiles | ForEach-Object {
        $match = [regex]::Match($_.BaseName, $renamedPattern)
        if ($match.Success) { $match.Groups[1].Value.Length }
    } | Measure-Object -Maximum).Maximum
    $existingWidthValue = if ($null -eq $existingWidth) { 0 } else { [int]$existingWidth }
    # .NET Math.Max has two-argument overloads only (including in Windows PowerShell 5.1).
    $padding = [int][Math]::Max([Math]::Max($minimumPadding, $lastNumber.ToString().Length), $existingWidthValue)
    $plan = for ($i = 0; $i -lt $ordered.Count; $i++) {
        $number = [Int64]($highestExisting + $i + 1)
        $newName = '{0}_{1}{2}' -f $prefix, $number.ToString(('D{0}' -f $padding)), $ordered[$i].File.Extension
        [pscustomobject]@{ OldPath=$ordered[$i].File.FullName; OldName=$ordered[$i].File.Name; NewName=$newName; NewPath=(Join-Path $TargetPath $newName); DateSource=$ordered[$i].DateSource; SortDate=$ordered[$i].SortDate }
    }

    $collisions = @($plan | Where-Object { (Test-Path -LiteralPath $_.NewPath) -and $_.NewPath -ne $_.OldPath })
    $duplicateTargets = @($plan | Group-Object NewPath | Where-Object Count -gt 1)
    if ($collisions.Count -or $duplicateTargets.Count) {
        foreach ($item in $collisions) { Write-RunLog "Collision: target already exists: $($item.NewPath)" 'ERROR' }
        foreach ($group in $duplicateTargets) { Write-RunLog "Collision: planned target is duplicated: $($group.Name)" 'ERROR' }
        throw 'No files were changed because the rename plan has collisions.'
    }

    Write-Host "`nPlan: rename $($plan.Count) file(s); skip $skipped; numbering $($highestExisting + 1) through $lastNumber; padding $padding."
    $plan | Select-Object OldName,NewName,DateSource | Format-Table -AutoSize | Out-Host
    if ($isDryRun) { Write-RunLog 'Dry run complete. No files, metadata, or undo log were changed.'; return }
    if (-not $Force) {
        $operation = if ($removeMetadata -and $bakeOrientation) { 'bake supported image orientations and remove all writable metadata' } elseif ($removeMetadata) { 'remove all writable metadata' } else { 'leave metadata unchanged' }
        $answer = Read-Host "This will rename $($plan.Count) file(s) and $operation. Continue? [y/N]"
        if ($answer -notmatch '^(?i)y(es)?$') { Write-RunLog 'Cancelled by user before changes.' 'WARN'; return }
    }

    $completed = [System.Collections.Generic.List[object]]::new()
    try {
        for ($i = 0; $i -lt $plan.Count; $i++) {
            $item = $plan[$i]
            Write-Progress -Activity 'Renaming media' -Status "$($i + 1) of $($plan.Count): $($item.OldName)" -PercentComplete ((($i + 1) / $plan.Count) * 100)
            Rename-Item -LiteralPath $item.OldPath -NewName $item.NewName -ErrorAction Stop
            $completed.Add($item)
            Write-RunLog "Renamed '$($item.OldName)' -> '$($item.NewName)' [$($item.DateSource)]."
        }
    }
    catch {
        Write-RunLog "Rename failed: $($_.Exception.Message). Attempting rollback of $($completed.Count) file(s)." 'ERROR'
        foreach ($item in @($completed | Select-Object -Reverse)) {
            try { if ((Test-Path -LiteralPath $item.NewPath) -and -not (Test-Path -LiteralPath $item.OldPath)) { Rename-Item -LiteralPath $item.NewPath -NewName $item.OldName -ErrorAction Stop; Write-RunLog "Rolled back '$($item.NewName)'." 'WARN' } }
            catch { Write-RunLog "Rollback failed for '$($item.NewName)': $($_.Exception.Message)" 'ERROR' }
        }
        throw
    }
    finally { Write-Progress -Activity 'Renaming media' -Completed }

    $completed | Select-Object @{n='OldPath';e={$_.OldPath}}, @{n='NewPath';e={$_.NewPath}}, OldName, NewName, DateSource, SortDate | Export-Csv -LiteralPath $undoPath -NoTypeInformation -Encoding utf8
    Write-RunLog "Undo log written: $undoPath"

    if ($removeMetadata -and $completed.Count) {
        $orientationFiles = @($completed | Where-Object { $orientationExtensions -contains ([IO.Path]::GetExtension($_.NewPath).ToLowerInvariant()) })
        if ($bakeOrientation -and $orientationFiles.Count) {
            if (-not $imageMagick) { throw 'ImageMagick preflight state is unavailable; metadata removal was not started.' }
            # Do not use ImageMagick's @file-list syntax here. On Windows it can
            # misinterpret absolute drive-letter paths (for example E:\...) as a
            # malformed image name. Passing each literal path directly is robust.
            Write-RunLog "Baking orientation into $($orientationFiles.Count) supported image file(s)."
            for ($i = 0; $i -lt $orientationFiles.Count; $i++) {
                $image = $orientationFiles[$i]
                Write-Progress -Activity 'Baking image orientation' -Status "$($i + 1) of $($orientationFiles.Count): $($image.NewName)" -PercentComplete ((($i + 1) / $orientationFiles.Count) * 100)
                $orientationOutput = & $imageMagick mogrify -auto-orient $image.NewPath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "ImageMagick orientation normalization failed for '$($image.NewName)': $($orientationOutput -join [Environment]::NewLine)"
                }
            }
            Write-Progress -Activity 'Baking image orientation' -Completed
            Write-RunLog 'Image orientation normalization completed.'
        }
        Write-RunLog "Removing all writable metadata in one ExifTool invocation from $($completed.Count) file(s)."
        $metadataList = Join-Path $logDirectory ('PhotoOrganizer-metadata-{0}.txt' -f [guid]::NewGuid())
        try {
            [IO.File]::WriteAllLines($metadataList, [string[]]($completed | ForEach-Object NewPath), [Text.UTF8Encoding]::new($false))
            $output = & $exifTool -overwrite_original '-all=' -P -charset filename=UTF8 '-@' $metadataList 2>&1
            if ($LASTEXITCODE -ne 0) { throw "ExifTool metadata removal failed: $($output -join [Environment]::NewLine)" }
            Write-RunLog "ExifTool metadata removal completed: $($output -join ' ')"
        }
        finally { Remove-Item -LiteralPath $metadataList -Force -ErrorAction SilentlyContinue }
    }
    Write-RunLog "Completed successfully. Renamed=$($completed.Count); skipped=$skipped; metadataRemoved=$removeMetadata."
    Write-Host "`nComplete. Renamed: $($completed.Count). Skipped: $skipped. Log: $script:RunLogPath"
}
catch {
    if ($script:RunLogPath) { Write-RunLog $_.Exception.Message 'ERROR' }
    else { Write-Error $_.Exception.Message }
    exit 1
}
