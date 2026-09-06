#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path '..' 'SubtitleTools.psd1')
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path (Join-Path $PSScriptRoot '..') 'Fixtures'
}

Describe 'Test-SrtFile' {
    It 'Returns IsValid = true for a valid file' {
        $result = Test-SrtFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $result.IsValid | Should -Be $true
        $result.ErrorCount | Should -Be 0
    }

    It 'Returns a ValidationResult object' {
        $result = Test-SrtFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $result.GetType().Name | Should -Be 'ValidationResult'
    }

    It 'Accepts pipeline input' {
        $sub    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $result = $sub | Test-SrtFile
        $result.IsValid | Should -Be $true
    }
}

Describe 'Test-SubtitleOverlap' {
    It 'Detects overlapping entries' {
        $sub    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'overlapping_timestamps.srt')
        $result = $sub | Test-SubtitleOverlap
        $result.WarningCount | Should -BeGreaterThan 0
    }

    It 'Returns no warnings for non-overlapping file' {
        $sub    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $result = $sub | Test-SubtitleOverlap
        $result.WarningCount | Should -Be 0
    }
}

Describe 'Test-SubtitleTimestamps' {
    It 'Validates timestamps on a clean file' {
        $sub    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $result = $sub | Test-SubtitleTimestamps
        $result.IsValid | Should -Be $true
        $result.ErrorCount | Should -Be 0
    }
}

Describe 'Test-AssFile' {
    It 'Validates a well-formed ASS file' {
        $result = Test-AssFile -Path (Join-Path $FixturesPath 'valid_full.ass')
        $result.IsValid | Should -Be $true
    }
}
