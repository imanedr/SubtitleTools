function Merge-SubtitleFile {
    <#
    .SYNOPSIS
        Interleaves two SubtitleFile objects into one, sorted by start time.
    .DESCRIPTION
        Useful for combining forced subtitles with a full subtitle track, or
        merging subtitles from two sources.
    .PARAMETER Primary
        The primary SubtitleFile.
    .PARAMETER Secondary
        The SubtitleFile to merge into the primary.
    .EXAMPLE
        $merged = Merge-SubtitleFile -Primary $full -Secondary $forced
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory)]
        [SubtitleFile] $Primary,

        [Parameter(Mandatory)]
        [SubtitleFile] $Secondary
    )

    $merged = [SubtitleFile]::new()
    $merged.Format   = $Primary.Format
    $merged.Encoding = $Primary.Encoding
    $merged.Header   = $Primary.Header

    $allEntries = @($Primary.Entries) + @($Secondary.Entries)
    $sorted     = $allEntries | Sort-Object Start

    $i = 1
    foreach ($entry in $sorted) {
        $entry.Index = $i++
    }

    $merged.Entries = $sorted
    return $merged
}
