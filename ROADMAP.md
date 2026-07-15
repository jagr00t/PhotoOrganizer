# PhotoOrganizer roadmap

The project is developed in small, usable releases. Every milestone must retain dry-run support and be verified on copies of media, never on irreplaceable originals.

## v1.0 — usable core (current)

- Chronological one-folder rename workflow.
- ExifTool date lookup and metadata removal.
- Orientation baking with ImageMagick for supported raster images.
- Rename undo CSV and text logs.

## v1.1 — reliability and recovery

- Split the main script into focused PowerShell modules.
- Add a pre-run validation report: dependency versions, writable-folder check, filename-length check, and supported-format summary.
- Strengthen rollback reporting and add a post-run verification report.
- Add automated Pester tests for naming, date fallback, collision detection, and undo planning.

## v1.2 — auditability

- Add a JSON snapshot of the original names, file sizes, hashes, filesystem dates, and selected metadata before modification.
- Add CSV summary reports and a `-ReportOnly` mode.
- Add explicit per-file statuses for metadata and orientation processing.

## v1.3 — duplicate management

- SHA-256 duplicate detection.
- Report-only duplicate grouping as the default.
- Optional move-to-review-folder workflow; no automatic deletion.

## v1.4 — scale and configuration

- Recursive mode with an opt-in folder naming strategy.
- Configuration validation and custom naming templates.
- Performance profiling for large collections.

## v2.0 — distribution

- PowerShell module packaging.
- GitHub Actions checks, release notes, and signed release guidance.
- Optional Windows Explorer integration.

## Development rules

- Never make destructive behaviour the default.
- Keep all external-tool calls explicit and logged.
- Test against copies of representative JPEG, HEIC, TIFF, RAW, and video files.
- Do not add automatic deletion of files or backups.
