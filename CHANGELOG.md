# Changelog

All notable changes to PhotoOrganizer are documented here.

## Unreleased

### Added

- Project roadmap and initial test scaffold.

## 1.0.0 - 2026-07-15

### Added

- Single-folder media renaming in chronological order.
- Date priority: `DateTimeOriginal`, `CreateDate`, `LastWriteTimeUtc`, then `CreationTimeUtc`.
- Resume numbering, collision detection, dry-run mode, confirmation, undo CSV, text logs, and progress reporting.
- ExifTool discovery, one metadata-reading invocation, and one metadata-removal invocation.
- Optional ImageMagick orientation baking before metadata removal.

### Safety

- No overwrite behaviour.
- Rename rollback attempt on a rename failure.
- Metadata removal begins only after all renames succeed.
