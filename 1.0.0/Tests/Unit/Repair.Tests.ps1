#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\SubtitleTools.psd1'
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path $PSScriptRoot '..\Fixtures'
}

Describe 'Repair-SubtitleNumbering' {
    It 'Renumbers out-of-order block numbers sequentially' {
        $sub     = Import-SubtitleFile -Path (Join-Path $FixturesPath 'malformed_numbering.srt')
        $repaired = Repair-SubtitleNumbering -InputObject $sub
        $repaired.Entries[0].Index | Should -Be 1
        $repaired.Entries[1].Index | Should -Be 2
        $repaired.Entries[2].Index | Should -Be 3
    }
}

Describe 'Repair-SubtitleOverlap' {
    It 'Resolves overlaps with Trim strategy' {
        $sub      = Import-SubtitleFile -Path (Join-Path $FixturesPath 'overlapping_timestamps.srt')
        $repaired = $sub | Repair-SubtitleOverlap -Strategy Trim
        $overlap  = $repaired | Test-SubtitleOverlap
        $overlap.WarningCount | Should -Be 0
    }

    It 'Resolves overlaps with Drop strategy by removing overlapping entry' {
        $sub      = Import-SubtitleFile -Path (Join-Path $FixturesPath 'overlapping_timestamps.srt')
        $original = $sub.Entries.Count
        $repaired = $sub | Repair-SubtitleOverlap -Strategy Drop
        $repaired.Entries.Count | Should -BeLessThan $original
    }
}

Describe 'Repair-SrtFile' {
    It 'Returns a SubtitleFile with sequential numbering' {
        $repaired = Repair-SrtFile -Path (Join-Path $FixturesPath 'malformed_numbering.srt')
        $repaired.Entries[0].Index | Should -Be 1
        $repaired.Entries[-1].Index | Should -Be $repaired.Entries.Count
    }
}
