#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\SubtitleTools.psd1'
    Import-Module $ModulePath -Force
    $FixturesPath = Join-Path $PSScriptRoot '..\Fixtures'
}

Describe 'Add-SubtitleOffset' {
    It 'Shifts all entries by positive milliseconds' {
        $sub     = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $orig    = $sub.Entries[0].Start
        $shifted = $sub | Add-SubtitleOffset -Milliseconds 1000
        $shifted.Entries[0].Start | Should -Be ($orig + [TimeSpan]::FromMilliseconds(1000))
    }

    It 'Shifts entries by negative seconds (earlier)' {
        $sub     = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $orig    = $sub.Entries[2].Start   # 00:00:09
        $shifted = $sub | Add-SubtitleOffset -Seconds -2
        $shifted.Entries[2].Start | Should -Be ($orig - [TimeSpan]::FromSeconds(2))
    }

    It 'Clamps entries to zero when they would go negative' {
        $sub     = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $shifted = $sub | Add-SubtitleOffset -Seconds -100
        $shifted.Entries[0].Start | Should -Be ([TimeSpan]::Zero)
    }
}

Describe 'Get-SubtitleDuration' {
    It 'Returns a duration summary object' {
        $sub  = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $info = $sub | Get-SubtitleDuration
        $info | Should -Not -BeNullOrEmpty
        $info.EntryCount | Should -Be 3
        $info.FirstStart | Should -Be ([TimeSpan]::FromSeconds(1))
        $info.LastEnd    | Should -Be ([TimeSpan]::FromSeconds(12))
    }
}

Describe 'Invoke-SubtitleStretch' {
    It 'Stretches timestamps linearly between two sync points' {
        $sub = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')

        # Sync: entry at 1s should now be at 2s; entry at 9s should now be at 10s
        $src1 = [TimeSpan]::FromSeconds(1)
        $tgt1 = [TimeSpan]::FromSeconds(2)
        $src2 = [TimeSpan]::FromSeconds(9)
        $tgt2 = [TimeSpan]::FromSeconds(10)
        $stretched = $sub | Invoke-SubtitleStretch -SourcePoint1 $src1 -TargetPoint1 $tgt1 -SourcePoint2 $src2 -TargetPoint2 $tgt2

        # First entry should now start at ~2s (within 1ms tolerance)
        $actual = $stretched.Entries[0].Start.TotalSeconds
        $actual | Should -BeGreaterThan 1.999
        $actual | Should -BeLessThan 2.001
    }
}

Describe 'Merge-SubtitleFile' {
    It 'Interleaves two files sorted by start time' {
        $a    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $b    = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_multiline.srt')
        $merged = Merge-SubtitleFile -Primary $a -Secondary $b
        $merged.Entries.Count | Should -Be ($a.Entries.Count + $b.Entries.Count)

        # Should be sorted
        for ($i = 1; $i -lt $merged.Entries.Count; $i++) {
            $merged.Entries[$i].Start | Should -BeGreaterOrEqual $merged.Entries[$i-1].Start
        }
    }
}

Describe 'Split-SubtitleFile' {
    It 'Splits a file at a given time into two parts' {
        $sub   = Import-SubtitleFile -Path (Join-Path $FixturesPath 'valid_simple.srt')
        $parts = $sub | Split-SubtitleFile -AtTime ([TimeSpan]::FromSeconds(6))
        $parts.Count | Should -Be 2
        $parts[0].Entries.Count | Should -BeGreaterThan 0
        $parts[1].Entries.Count | Should -BeGreaterThan 0
        ($parts[0].Entries.Count + $parts[1].Entries.Count) | Should -Be $sub.Entries.Count
    }
}
