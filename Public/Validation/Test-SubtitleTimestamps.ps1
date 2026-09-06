function Test-SubtitleTimestamps {
    <#
    .SYNOPSIS
        Validates that all entries have end > start and non-negative start times.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Test-SubtitleTimestamps
    #>
    [CmdletBinding()]
    [OutputType('ValidationResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        $result          = [ValidationResult]::new()
        $result.FilePath = $InputObject.Path
        $result.Format   = $InputObject.Format

        foreach ($entry in $InputObject.Entries) {
            $i = $entry.Index

            if ($entry.Start -lt [TimeSpan]::Zero) {
                $result.AddError($i, 'Start', "Negative start time: $($entry.Start).")
            }

            if ($entry.End -lt [TimeSpan]::Zero) {
                $result.AddError($i, 'End', "Negative end time: $($entry.End).")
            }

            if ($entry.End -lt $entry.Start) {
                $result.AddError($i, 'Timestamp', "End ($($entry.End)) is before Start ($($entry.Start)).")
            }

            if ($entry.Start -eq $entry.End) {
                $result.AddWarning($i, 'Timestamp', 'Zero-duration entry (Start == End).')
            }
        }

        return $result
    }
}
