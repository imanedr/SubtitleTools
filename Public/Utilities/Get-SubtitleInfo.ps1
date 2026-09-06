function Get-SubtitleInfo {
    <#
    .SYNOPSIS
        Returns a summary object describing a subtitle file.
    .DESCRIPTION
        Reports: file path, format, entry count, encoding, BOM presence,
        total duration, has overlaps, has parser warnings.
    .PARAMETER Path
        Path to a subtitle file.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Get-SubtitleInfo -Path 'movie.srt'
    .EXAMPLE
        Get-ChildItem *.srt | Get-SubtitleInfo
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [SubtitleFile] $InputObject
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $InputObject = Import-SubtitleFile -Path $Path
        }

        $duration    = Get-SubtitleDuration -InputObject $InputObject
        $overlapTest = Test-SubtitleOverlap -InputObject $InputObject

        [PSCustomObject]@{
            Path           = $InputObject.Path
            Format         = $InputObject.Format
            EntryCount     = $InputObject.Entries.Count
            Encoding       = $InputObject.Encoding
            HasBom         = $InputObject.HasBom
            FirstStart     = $duration.FirstStart
            LastEnd        = $duration.LastEnd
            TotalSpan      = $duration.TotalSpan
            TotalDisplay   = $duration.TotalDisplayTime
            AvgDuration    = $duration.AverageDuration
            HasOverlaps    = ($overlapTest.WarningCount -gt 0)
            OverlapCount   = $overlapTest.WarningCount
            ParserWarnings = $InputObject.ParserWarnings.Count
            StyleCount     = if ($InputObject.Header) { $InputObject.Header.Styles.Count } else { $null }
        }
    }
}
