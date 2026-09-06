function Optimize-SubtitleFile {
    <#
    .SYNOPSIS
        Non-destructive cleanup: removes duplicates, sorts by start time, trims whitespace.
    .DESCRIPTION
        Performs the following optimizations:
        - Sort entries by start time
        - Remove exact duplicate entries (same start, end, and text)
        - Remove entries with no visible text
        - Trim leading/trailing whitespace from each line
        - Normalize Unicode (NFC)
        - Re-index from 1
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Optimize-SubtitleFile
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        # Sort by start time
        $sorted = @($InputObject.Entries | Sort-Object Start, End)

        # Remove duplicates (same start+end+text)
        $seen    = [System.Collections.Generic.HashSet[string]]::new()
        $deduped = [System.Collections.Generic.List[SubtitleEntry]]::new()

        foreach ($entry in $sorted) {
            $key = '{0}|{1}|{2}' -f $entry.Start.Ticks, $entry.End.Ticks, ($entry.Lines -join '|')
            if ($seen.Add($key)) {
                $deduped.Add($entry)
            }
        }

        # Trim whitespace and normalize Unicode on each line
        foreach ($entry in $deduped) {
            $entry.Lines = $entry.Lines |
                ForEach-Object { $_.Trim().Normalize([System.Text.NormalizationForm]::FormC) } |
                Where-Object { $_ -ne '' }
        }

        # Remove entries with no visible text
        $cleaned = @($deduped | Where-Object { $_.Lines.Count -gt 0 })

        # Re-index
        $i = 1
        foreach ($entry in $cleaned) {
            $entry.Index = $i
            if ($entry -is [SrtEntry]) { $entry.BlockNumber = $i }
            $i++
        }

        $InputObject.Entries = $cleaned
        Write-SubtitleLog -Message "Optimized: $($cleaned.Count) entries after dedup/sort/trim." -Level Info
        return $InputObject
    }
}
