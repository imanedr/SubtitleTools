function Get-SubtitleDuration {
    <#
    .SYNOPSIS
        Returns duration statistics for a SubtitleFile.
    .DESCRIPTION
        Reports: total span (first start to last end), average entry duration,
        shortest and longest entry durations, and total display time.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Get-SubtitleDuration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        if ($InputObject.Entries.Count -eq 0) {
            return [PSCustomObject]@{
                EntryCount        = 0
                FirstStart        = [TimeSpan]::Zero
                LastEnd           = [TimeSpan]::Zero
                TotalSpan         = [TimeSpan]::Zero
                TotalDisplayTime  = [TimeSpan]::Zero
                AverageDuration   = [TimeSpan]::Zero
                ShortestDuration  = [TimeSpan]::Zero
                LongestDuration   = [TimeSpan]::Zero
            }
        }

        $sorted      = $InputObject.Entries | Sort-Object Start
        $firstStart  = $sorted[0].Start
        $lastEnd     = ($sorted | Sort-Object End | Select-Object -Last 1).End
        $durations   = $sorted | ForEach-Object { $_.End - $_.Start }
        $totalMs     = ($durations | Measure-Object -Property TotalMilliseconds -Sum).Sum
        $avgMs       = $totalMs / $durations.Count
        $minMs       = ($durations | Measure-Object -Property TotalMilliseconds -Minimum).Minimum
        $maxMs       = ($durations | Measure-Object -Property TotalMilliseconds -Maximum).Maximum

        return [PSCustomObject]@{
            EntryCount       = $InputObject.Entries.Count
            FirstStart       = $firstStart
            LastEnd          = $lastEnd
            TotalSpan        = $lastEnd - $firstStart
            TotalDisplayTime = [TimeSpan]::FromMilliseconds($totalMs)
            AverageDuration  = [TimeSpan]::FromMilliseconds($avgMs)
            ShortestDuration = [TimeSpan]::FromMilliseconds($minMs)
            LongestDuration  = [TimeSpan]::FromMilliseconds($maxMs)
        }
    }
}
