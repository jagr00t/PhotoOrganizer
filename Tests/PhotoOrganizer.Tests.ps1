# Requires -Version 5.1
# Initial Pester test scaffold. The v1.1 milestone will expose internal functions
# from a module so these tests can exercise behavior without touching real media.

Describe 'PhotoOrganizer project layout' {
    $root = Split-Path -Parent $PSScriptRoot

    It 'contains the main utility' {
        Test-Path -LiteralPath (Join-Path $root 'PhotoOrganizer.ps1') | Should -BeTrue
    }

    It 'contains an undo utility' {
        Test-Path -LiteralPath (Join-Path $root 'Undo-PhotoOrganizer.ps1') | Should -BeTrue
    }

    It 'contains valid JSON configuration' {
        { Get-Content -LiteralPath (Join-Path $root 'PhotoOrganizer.json') -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
}
