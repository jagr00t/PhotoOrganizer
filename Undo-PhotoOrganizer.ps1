<#
.SYNOPSIS
  Restores names recorded by PhotoOrganizer.ps1's CSV undo log.

.EXAMPLE
  .\Undo-PhotoOrganizer.ps1 -UndoLog 'D:\Photos\Japan Trip\PhotoOrganizer-Logs\Undo_2026-07-14_10-00-00.csv' -DryRun

.EXAMPLE
  .\Undo-PhotoOrganizer.ps1 -UndoLog 'D:\Photos\Japan Trip\PhotoOrganizer-Logs\Undo_2026-07-14_10-00-00.csv' -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })] [string]$UndoLog,
    [switch]$DryRun,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    $entries = @(Import-Csv -LiteralPath $UndoLog)
    if (-not $entries.Count) { throw 'The undo log contains no entries.' }
    $problems = @($entries | Where-Object { -not (Test-Path -LiteralPath $_.NewPath) -or (Test-Path -LiteralPath $_.OldPath) })
    if ($problems.Count) {
        $problems | ForEach-Object { Write-Error "Cannot safely undo '$($_.NewName)': new file missing or original path already exists." }
        throw 'Undo stopped; no files were changed.'
    }
    Write-Host "Plan: restore $($entries.Count) original filename(s)."
    $entries | Select-Object NewName,OldName | Format-Table -AutoSize | Out-Host
    if ($DryRun) { Write-Host 'Dry run complete. No files were changed.'; return }
    if (-not $Force) { if ((Read-Host 'Restore these names? [y/N]') -notmatch '^(?i)y(es)?$') { Write-Host 'Cancelled.'; return } }
    $done = [System.Collections.Generic.List[object]]::new()
    try {
        for ($i=0; $i -lt $entries.Count; $i++) {
            $entry = $entries[$i]
            Write-Progress -Activity 'Restoring filenames' -Status "$($i + 1) of $($entries.Count)" -PercentComplete ((($i + 1)/$entries.Count)*100)
            Rename-Item -LiteralPath $entry.NewPath -NewName $entry.OldName -ErrorAction Stop
            $done.Add($entry)
        }
    }
    finally { Write-Progress -Activity 'Restoring filenames' -Completed }
    Write-Host "Restored $($done.Count) filename(s). Metadata cannot be restored."
}
catch { Write-Error $_.Exception.Message; exit 1 }
