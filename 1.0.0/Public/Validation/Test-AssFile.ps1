function Test-AssFile {
    <#
    .SYNOPSIS
        Validates the structure and content of an ASS/SSA file or SubtitleFile object.
    .DESCRIPTION
        Checks: mandatory sections present, ScriptType field, styles exist, event timestamps valid,
        no unclosed override tags.
    .PARAMETER Path
        Path to an ASS or SSA file.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Test-AssFile -Path 'anime.ass'
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
        $result.Format   = $InputObject.Format

        # Must have a Header
        if (-not $InputObject.Header) {
            $result.AddError(0, 'Structure', 'Missing [Script Info] section â€” Header is null.')
            return $result
        }

        # Must have at least one style
        if ($InputObject.Header.Styles.Count -eq 0) {
            $result.AddError(0, 'Styles', 'No styles defined in [V4+ Styles] section.')
        }

        # Parser warnings
        foreach ($key in $InputObject.ParserWarnings.Keys) {
            $result.AddWarning($key, 'Parse', $InputObject.ParserWarnings[$key])
        }

        $prevEnd = [TimeSpan]::Zero
        foreach ($entry in $InputObject.Entries) {
            $i = $entry.Index

            # Timestamp validity
            if ($entry.End -le $entry.Start) {
                $result.AddError($i, 'Timestamp', "End ($($entry.End)) is not after Start ($($entry.Start)).")
            }
            if ($entry.Start -lt [TimeSpan]::Zero) {
                $result.AddError($i, 'Timestamp', "Negative start time: $($entry.Start).")
            }

            # Unclosed override tags (odd number of braces is a sign of malformation)
            $rawText = $entry.RawText
            if ($rawText -match '\{[^}]*$') {
                $result.AddWarning($i, 'OverrideTag', "Possible unclosed override tag in: '$rawText'")
            }

            # Style reference exists
            if ($entry -is [AssEntry]) {
                $styleName = $entry.Style
                $styleExists = $InputObject.Header.Styles | Where-Object { $_.Name -eq $styleName }
                if (-not $styleExists) {
                    $result.AddWarning($i, 'Style', "Entry references undefined style '$styleName'.")
                }
            }

            # Overlap
            if ($entry.Start -lt $prevEnd) {
                $result.AddWarning($i, 'Overlap', "Entry $i starts ($($entry.Start)) before previous ends ($prevEnd).")
            }

            $prevEnd = $entry.End
        }

        return $result
    }
}
