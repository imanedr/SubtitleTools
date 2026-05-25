function Add-SubtitleOffset {
    <#
    .SYNOPSIS
        Shifts all subtitle timestamps by a given offset (positive or negative).
    .DESCRIPTION
        Adds the specified TimeSpan to both Start and End of every entry.
        Negative values shift subtitles earlier. By default, entries that would
        become negative are clamped to zero. Use -AllowNegative to disable this.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER Offset
        A TimeSpan representing the shift amount. Use negative values for earlier.
        Alternatively use -Milliseconds, -Seconds, or -Minutes for convenience.
    .PARAMETER Milliseconds
        Offset in milliseconds.
    .PARAMETER Seconds
        Offset in seconds.
    .PARAMETER Minutes
        Offset in minutes.
    .PARAMETER EntryRange
        Limit the offset to a range of entry indices, e.g. 10..50.
    .PARAMETER AllowNegative
        Do not clamp entries to zero when they would become negative.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Add-SubtitleOffset -Seconds 2.5
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Add-SubtitleOffset -Milliseconds -500
    #>
    [CmdletBinding(DefaultParameterSetName = 'Offset')]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Offset')]
        [TimeSpan] $Offset,

        [Parameter(Mandatory, ParameterSetName = 'Milliseconds')]
        [double] $Milliseconds,

        [Parameter(Mandatory, ParameterSetName = 'Seconds')]
        [double] $Seconds,

        [Parameter(Mandatory, ParameterSetName = 'Minutes')]
        [double] $Minutes,

        [int[]] $EntryRange,

        [switch] $AllowNegative
    )

    process {
        $shift = switch ($PSCmdlet.ParameterSetName) {
            'Offset'       { $Offset }
            'Milliseconds' { [TimeSpan]::FromMilliseconds($Milliseconds) }
            'Seconds'      { [TimeSpan]::FromSeconds($Seconds) }
            'Minutes'      { [TimeSpan]::FromMinutes($Minutes) }
        }

        $useRange = $EntryRange -and $EntryRange.Count -gt 0
        $rangeSet = if ($useRange) { [System.Collections.Generic.HashSet[int]]::new($EntryRange) } else { $null }

        foreach ($entry in $InputObject.Entries) {
            if ($useRange -and -not $rangeSet.Contains($entry.Index)) { continue }

            $newStart = $entry.Start + $shift
            $newEnd   = $entry.End   + $shift

            if (-not $AllowNegative) {
                if ($newStart -lt [TimeSpan]::Zero) { $newStart = [TimeSpan]::Zero }
                if ($newEnd   -lt [TimeSpan]::Zero) { $newEnd   = [TimeSpan]::Zero }
            }

            $entry.Start = $newStart
            $entry.End   = $newEnd
        }

        return $InputObject
    }
}
