function Compare-SubtitleFile {
    <#
    .SYNOPSIS
        Compares two SubtitleFile objects entry-by-entry and reports differences.
    .DESCRIPTION
        Matches entries by index. Reports: timestamp differences and text divergences.
        Useful for reviewing translated subtitles vs. source.
    .PARAMETER Reference
        The reference (original) SubtitleFile.
    .PARAMETER Difference
        The file to compare against the reference.
    .PARAMETER TextOnly
        Only report text differences (ignore timestamp differences).
    .EXAMPLE
        Compare-SubtitleFile -Reference $original -Difference $translated
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [SubtitleFile] $Reference,

        [Parameter(Mandatory)]
        [SubtitleFile] $Difference,

        [switch] $TextOnly
    )

    $maxIndex = [Math]::Max($Reference.Entries.Count, $Difference.Entries.Count)
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($i = 0; $i -lt $maxIndex; $i++) {
        $ref  = if ($i -lt $Reference.Entries.Count)  { $Reference.Entries[$i]  } else { $null }
        $diff = if ($i -lt $Difference.Entries.Count) { $Difference.Entries[$i] } else { $null }

        $changes = [System.Collections.Generic.List[string]]::new()

        if (-not $ref) {
            $changes.Add("Entry $($i+1) only in Difference")
        } elseif (-not $diff) {
            $changes.Add("Entry $($i+1) only in Reference")
        } else {
            if (-not $TextOnly) {
                if ($ref.Start -ne $diff.Start) {
                    $changes.Add("Start: $($ref.Start) → $($diff.Start)")
                }
                if ($ref.End -ne $diff.End) {
                    $changes.Add("End: $($ref.End) → $($diff.End)")
                }
            }

            $refText  = $ref.Lines  -join ' '
            $diffText = $diff.Lines -join ' '
            if ($refText -ne $diffText) {
                $changes.Add("Text: '$refText' → '$diffText'")
            }
        }

        if ($changes.Count -gt 0) {
            $results.Add([PSCustomObject]@{
                Index     = $i + 1
                Changes   = $changes.ToArray()
                Reference = $ref
                Difference = $diff
            })
        }
    }

    return $results.ToArray()
}
