function Set-SubtitleOffset {
    <#
    .SYNOPSIS
        Sets the absolute start time of the first entry and shifts all others by the same delta.
    .DESCRIPTION
        Useful when you know what time the first subtitle should appear and want to
        align the entire file to that anchor point.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER StartTime
        The desired start time for the first entry (or the anchor entry).
    .PARAMETER AnchorIndex
        Index of the entry to use as the anchor. Defaults to the first entry (1).
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Set-SubtitleOffset -StartTime '00:01:30.000'
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory)]
        [TimeSpan] $StartTime,

        [int] $AnchorIndex = 1
    )

    process {
        $anchor = $InputObject.Entries | Where-Object { $_.Index -eq $AnchorIndex } | Select-Object -First 1

        if (-not $anchor) {
            Write-Warning "Entry with index $AnchorIndex not found. Using first entry."
            $anchor = $InputObject.Entries | Select-Object -First 1
        }

        if (-not $anchor) {
            Write-Warning 'No entries found. Nothing to shift.'
            return $InputObject
        }

        $delta = $StartTime - $anchor.Start
        return Add-SubtitleOffset -InputObject $InputObject -Offset $delta
    }
}
