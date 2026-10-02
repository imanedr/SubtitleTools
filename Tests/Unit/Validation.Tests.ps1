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

Describe 'Test-SubtitleTranslation' {
    BeforeAll {
        # Builds an in-memory SRT whose entry N spans N..N+1 seconds.
        function New-TestSubtitle {
            param([string[]] $Texts)
            InModuleScope SubtitleTools -Parameters @{ texts = $Texts } {
                param($texts)
                $file        = [SubtitleFile]::new()
                $file.Format = 'SRT'
                $file.Entries = @(for ($i = 0; $i -lt $texts.Count; $i++) {
                    $e       = [SrtEntry]::new()
                    $e.Index = $i + 1
                    $e.Start = [TimeSpan]::FromSeconds($i + 1)
                    $e.End   = [TimeSpan]::FromSeconds($i + 2)
                    $e.Lines = @($texts[$i] -split "`n")
                    $e
                })
                $file
            }
        }
    }

    It 'Passes a clean translation' {
        $src = New-TestSubtitle 'Hello', 'Goodbye'
        $dst = New-TestSubtitle 'Salam', 'Khodahafez'
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.IsValid      | Should -BeTrue
        $result.WarningCount | Should -Be 0
    }

    It 'Errors when a timestamp changed' {
        $src = New-TestSubtitle 'Hello', 'Goodbye'
        $dst = New-TestSubtitle 'Salam', 'Khodahafez'
        $dst.Entries[1].End = [TimeSpan]::FromSeconds(9)
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.IsValid | Should -BeFalse
        $result.Errors.Field      | Should -Contain 'Timestamp'
        $result.Errors.EntryIndex | Should -Contain 2
    }

    It 'Errors when the entry count differs' {
        $src = New-TestSubtitle 'Hello', 'Goodbye'
        $dst = New-TestSubtitle 'Salam'
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.Errors.Field | Should -Contain 'Count'
    }

    It 'Errors on an empty translation of a non-empty entry' {
        $src = New-TestSubtitle 'Hello'
        $dst = New-TestSubtitle ' '
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.Errors.Field | Should -Contain 'Text'
    }

    It 'Warns on untranslated text but not on text without letters' {
        $src = New-TestSubtitle 'Hello', '...', '♪'
        $dst = New-TestSubtitle 'Hello', '...', '♪'
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.IsValid | Should -BeTrue
        @($result.Warnings | Where-Object Field -eq 'Untranslated').EntryIndex | Should -Be @(1)
    }

    It 'Warns on leftover batch markers' {
        $src = New-TestSubtitle 'Hello', 'Goodbye'
        $dst = New-TestSubtitle '1|Salam', 'Khoda<NL>hafez'
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        @($result.Warnings | Where-Object Field -eq 'Format').Count | Should -Be 2
    }

    It 'Downgrades timestamp problems inherited from the source to warnings' {
        $src = New-TestSubtitle 'Hello'
        $dst = New-TestSubtitle 'Salam'
        $src.Entries[0].End = [TimeSpan]::Zero
        $dst.Entries[0].End = [TimeSpan]::Zero
        $result = Test-SubtitleTranslation -Source $src -Translated $dst
        $result.IsValid | Should -BeTrue
        $result.Warnings.Message | Should -Match 'also present in source'
    }

    It 'Warns when ASS override tags were lost' {
        $src = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_full.ass')
        $path = Join-Path $TestDrive 'roundtrip.ass'
        Export-SubtitleFile -InputObject $src -Path $path
        $result = Test-SubtitleTranslation -Source $src -Translated (Import-SubtitleFile -Path $path)
        $result.Warnings.Field | Should -Contain 'OverrideTag'
    }
}
