function Test-SrtFile {
    <#
    .SYNOPSIS
        Validates the structure and content of an SRT file or SubtitleFile object.
    .DESCRIPTION
        Checks: block sequence, timestamp format, end > start, non-empty text, overlaps.
        Returns a ValidationResult object.
    .PARAMETER Path
        Path to an SRT file.
    .PARAMETER InputObject
        A SubtitleFile object (must be SRT format).
    .EXAMPLE
        Test-SrtFile -Path 'movie.srt'
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Test-SrtFile
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('ValidationResult')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Object')]
        [SubtitleFile] $InputObject
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $InputObject = Import-SubtitleFile -Path $Path
        }

        $result          = [ValidationResult]::new()
        $result.FilePath = $InputObject.Path
        $result.Format   = 'SRT'

        # Report parser warnings as ValidationResult warnings
        foreach ($key in $InputObject.ParserWarnings.Keys) {
            $result.AddWarning($key, 'Parse', $InputObject.ParserWarnings[$key])
        }

        $prevEnd = [TimeSpan]::Zero
        foreach ($entry in $InputObject.Entries) {
            $i = $entry.Index

            # End must be after Start
            if ($entry.End -le $entry.Start) {
                $result.AddError($i, 'Timestamp', "End time ($($entry.End)) is not after Start time ($($entry.Start)).")
            }

            # Start must be non-negative
            if ($entry.Start -lt [TimeSpan]::Zero) {
                $result.AddError($i, 'Timestamp', "Start time is negative: $($entry.Start).")
            }

            # Zero-duration warning
            if ($entry.Start -eq $entry.End) {
                $result.AddWarning($i, 'Timestamp', 'Entry has zero duration (Start == End).')
            }

            # Empty text warning
            if ($entry.Lines.Count -eq 0 -or ($entry.Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -eq $null) {
                $result.AddWarning($i, 'Text', 'Entry has no visible text.')
            }

            # Overlap with previous entry
            if ($entry.Start -lt $prevEnd) {
                $result.AddWarning($i, 'Overlap', "Entry $i starts ($($entry.Start)) before previous entry ends ($prevEnd).")
            }

            $prevEnd = $entry.End
        }

        return $result
    }
}
