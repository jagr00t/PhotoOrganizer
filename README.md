# PhotoOrganizer v1.0

PhotoOrganizer renames supported media files in a single folder in chronological order, then optionally removes all writable metadata. It uses ExifTool to read capture dates and remove metadata.

## Important safety notes

- Make a backup first. Renaming can be undone with the generated CSV log; removed metadata cannot be recovered.
- The application asks for confirmation before it changes files. Always review a dry run first.
- This tool processes only the chosen folder, not subfolders.
- `-all=` removes all writable metadata, including capture dates, GPS, camera information, thumbnails, authors, and original-file-name tags. The date is used only to decide ordering before removal.

## Requirements

1. Windows PowerShell 5.1 or PowerShell 7.
2. [ExifTool](https://exiftool.org/) installed and available as `exiftool` in `PATH`.
3. [ImageMagick](https://imagemagick.org/) installed and available as `magick` in `PATH` when `BakeOrientation` is enabled (it is enabled by default).

Check the requirement in a new PowerShell window:

```powershell
exiftool -ver
magick -version
```

## Files

- `PhotoOrganizer.ps1` — organizer.
- `Undo-PhotoOrganizer.ps1` — restores names from one CSV undo log.
- `PhotoOrganizer.json` — safe default settings and supported extensions.

## Usage

Open PowerShell and run a preview first:

```powershell
& 'C:\path\to\PhotoOrganizer.ps1' -TargetPath 'D:\Photos\Japan Trip' -DryRun
```

The script prints every proposed old/new name and makes no changes.

After checking both the preview and your backup, apply it:

```powershell
& 'C:\path\to\PhotoOrganizer.ps1' -TargetPath 'D:\Photos\Japan Trip' -Force
```

`-DryRun` always forces a preview. Omit `-Force` if you prefer the confirmation prompt (recommended).

To rename without metadata removal for a specific run:

```powershell
& 'C:\path\to\PhotoOrganizer.ps1' -TargetPath 'D:\Photos\Japan Trip' -NoMetadata
```

To use the current PowerShell folder, omit `-TargetPath`:

```powershell
Set-Location 'D:\Photos\Japan Trip'
& 'C:\path\to\PhotoOrganizer.ps1'
```

## Naming and ordering

The current folder name is made safe for Windows filenames and used as the prefix. `Japan: Trip?` becomes `Japan Trip`. Existing files such as `Japan Trip_001.jpg` are skipped. New files continue after the highest existing number.

Numbers use at least three digits and expand when needed: `001` through `999`, then `1000`. Existing padding is retained if it is wider.

Files are sorted by, in order:

1. ExifTool `DateTimeOriginal`;
2. ExifTool `CreateDate`;
3. filesystem `LastWriteTimeUtc`;
4. filesystem `CreationTimeUtc`.

## Orientation handling

Before metadata is removed, the default `"BakeOrientation": true` uses ImageMagick to physically normalize supported image files (JPEG, PNG, WebP, TIFF, HEIC and HEIF). The EXIF orientation tag can then be removed without changing how those images display. RAW files and videos are not physically rotated by this utility. If ImageMagick is unavailable, the application stops before renaming or removing metadata rather than risking an incorrectly oriented result.

ImageMagick rewrites normalized images; keep your backup and inspect a small test folder first. Set `"BakeOrientation": false` only if you accept the orientation risk described above.

Supported formats include common JPEG/HEIC/PNG/TIFF images, CR2/CR3/NEF/ARW/DNG and other RAW files, and MP4/MOV/AVI/MKV/MTS/M2TS/3GP videos. Change `SupportedExtensions` in `PhotoOrganizer.json` to adjust the list.

## Logs and undo

Each applied run writes `PhotoOrganizer-Logs` inside the target folder:

- `Run_*.txt` describes the run and any errors.
- `Undo_*.csv` maps original paths to renamed paths.

Preview runs write a text log only. To preview an undo:

```powershell
& 'C:\path\to\Undo-PhotoOrganizer.ps1' -UndoLog 'D:\Photos\Japan Trip\PhotoOrganizer-Logs\Undo_YYYY-MM-DD_HH-mm-ss.csv' -DryRun
```

Apply an undo after reviewing it:

```powershell
& 'C:\path\to\Undo-PhotoOrganizer.ps1' -UndoLog 'D:\Photos\Japan Trip\PhotoOrganizer-Logs\Undo_YYYY-MM-DD_HH-mm-ss.csv' -Force
```

Undo restores names only. It cannot restore metadata removed by ExifTool.
