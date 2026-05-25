function Test-SubtitleOverlap {
    <#
    .SYNOPSIS
        Detects entries where one entry's start time is before the previous entry's end time.
    .DESCRIPTION
        Returns a ValidationResult with each overlapping pair described in the warnings.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Test-SubtitleOverlap
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

        $sorted = $InputObject.Entries | Sort-Object Start

        for ($i = 1; $i -lt $sorted.Count; $i++) {
            $prev = $sorted[$i - 1]
            $curr = $sorted[$i]

            if ($curr.Start -lt $prev.End) {
                $overlap = $prev.End - $curr.Start
                $result.AddWarning(
                    $curr.Index,
                    'Overlap',
                    "Entry $($curr.Index) starts $overlap before entry $($prev.Index) ends. ($($curr.Start) < $($prev.End))"
                )
            }
        }

        return $result
    }
}
