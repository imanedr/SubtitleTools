#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path '..' 'SubtitleTools.psd1')
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path (Join-Path $PSScriptRoot '..') 'Fixtures'
}

Describe 'Import-SubtitleFile' {
    Context 'SRT files' {
        It 'Parses a valid simple SRT file' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
            $sub | Should -Not -BeNullOrEmpty
            $sub.Format | Should -Be 'SRT'
            $sub.Entries.Count | Should -Be 3
        }

        It 'Returns a SubtitleFile object' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
            $sub.GetType().Name | Should -Be 'SubtitleFile'
        }

        It 'Parses timestamps as TimeSpan' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
            $sub.Entries[0].Start | Should -BeOfType [TimeSpan]
            $sub.Entries[0].Start | Should -Be ([TimeSpan]::FromSeconds(1))
            $sub.Entries[0].End   | Should -Be ([TimeSpan]::FromSeconds(4))
        }

        It 'Parses multiline subtitles correctly' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_multiline.srt')
            $sub.Entries[0].Lines.Count | Should -Be 2
        }

        It 'Detects HTML tags' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_multiline.srt')
            $sub.Entries[1].HasHtmlTags | Should -Be $true
        }

        It 'Handles dot separator timestamps with a warning' {
            { Import-SubtitleFile -Path (Join-Path $FixturesPath 'dot_separator.srt') } | Should -Not -Throw
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'dot_separator.srt')
            $sub.Entries.Count | Should -Be 2
        }
    }

    Context 'ASS files' {
        It 'Parses a valid ASS file' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_full.ass')
            $sub | Should -Not -BeNullOrEmpty
            $sub.Format | Should -Be 'ASS'
            $sub.Entries.Count | Should -Be 3
        }

        It 'Populates Header styles' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_full.ass')
            $sub.Header | Should -Not -BeNullOrEmpty
            $sub.Header.Styles.Count | Should -BeGreaterThan 0
        }

        It 'Parses ASS timestamps correctly' {
            $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_full.ass')
            $sub.Entries[0].Start | Should -Be ([TimeSpan]::FromSeconds(1))
        }
    }
}

Describe 'ConvertTo-SrtFile / ConvertFrom-SrtFile round-trip' {
    It 'Round-trips a simple SRT without data loss' {
        $original  = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $serialized = ConvertTo-SrtFile -InputObject $original
        $reparsed   = ConvertFrom-SrtFile -Content $serialized

        $reparsed.Count | Should -Be $original.Entries.Count

        for ($i = 0; $i -lt $reparsed.Count; $i++) {
            $reparsed[$i].Start | Should -Be $original.Entries[$i].Start
            $reparsed[$i].End   | Should -Be $original.Entries[$i].End
            ($reparsed[$i].Lines -join ' ') | Should -Be ($original.Entries[$i].Lines -join ' ')
        }
    }
}

Describe 'Export-SubtitleFile' {
    It 'Writes a file to disk without error' {
        $sub  = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $dest = Join-Path $TestDrive 'output.srt'
        { Export-SubtitleFile -InputObject $sub -Path $dest } | Should -Not -Throw
        Test-Path $dest | Should -Be $true
    }

    It 'Written file can be re-imported' {
        $sub  = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $dest = Join-Path $TestDrive 'output2.srt'
        Export-SubtitleFile -InputObject $sub -Path $dest
        $reimported = Import-SubtitleFile -Path $dest
        $reimported.Entries.Count | Should -Be $sub.Entries.Count
    }
}
