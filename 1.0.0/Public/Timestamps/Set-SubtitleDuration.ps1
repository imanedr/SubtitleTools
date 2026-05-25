function Set-SubtitleDuration {
    <#
    .SYNOPSIS
        Clamps or extends the display duration of each entry to a specified min/max range.
    .DESCRIPTION
        Use -Minimum to ensure entries display for at least N milliseconds.
        Use -Maximum to cap long entries.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER Minimum
        Minimum display duration as a TimeSpan.
    .PARAMETER Maximum
        Maximum display duration as a TimeSpan.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Set-SubtitleDuration -Minimum (New-TimeSpan -Seconds 1)
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [TimeSpan] $Minimum,

        [TimeSpan] $Maximum
    )

    process {
        foreach ($entry in $InputObject.Entries) {
            $duration = $entry.End - $entry.Start

            if ($Minimum -and $duration -lt $Minimum) {
                $entry.End = $entry.Start + $Minimum
            }

            if ($Maximum -and $duration -gt $Maximum) {
                $entry.End = $entry.Start + $Maximum
            }
        }

        return $InputObject
    }
}
