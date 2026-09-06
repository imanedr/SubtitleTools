function Repair-SubtitleOverlap {
    <#
    .SYNOPSIS
        Resolves timestamp overlaps between subtitle entries.
    .DESCRIPTION
        Three strategies:
        - Trim (default): shorten the earlier entry's end time to the start of the next.
        - Shift: push the later entry forward to start after the previous ends.
        - Drop: remove the entry that starts before the previous one ends.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER Strategy
        Overlap resolution strategy: Trim, Shift, or Drop.
    .PARAMETER Gap
        Minimum gap in milliseconds to insert between entries when using Trim or Shift. Default: 0.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Repair-SubtitleOverlap -Strategy Trim
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Repair-SubtitleOverlap -Strategy Shift -Gap 50
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [ValidateSet('Trim', 'Shift', 'Drop')]
        [string] $Strategy = 'Trim',

        [int] $Gap = 0
    )

    process {
        $gapSpan  = [TimeSpan]::FromMilliseconds($Gap)
        $sorted   = [System.Collections.Generic.List[SubtitleEntry]]::new()
        $sorted.AddRange([SubtitleEntry[]]($InputObject.Entries | Sort-Object Start))

        $repaired = [System.Collections.Generic.List[SubtitleEntry]]::new()
        $prevEnd  = [TimeSpan]::Zero

        foreach ($entry in $sorted) {
            if ($entry.Start -lt $prevEnd) {
                switch ($Strategy) {
                    'Trim' {
                        # Shorten the previous entry
                        if ($repaired.Count -gt 0) {
                            $lastRepaired = $repaired[$repaired.Count - 1]
                            $newEnd = $entry.Start - $gapSpan
                            if ($newEnd -gt $lastRepaired.Start) {
                                $lastRepaired.End = $newEnd
                            }
                        }
                        $repaired.Add($entry)
                        $prevEnd = $entry.End
                    }
                    'Shift' {
                        # Push this entry forward
                        $shift       = $prevEnd + $gapSpan - $entry.Start
                        $duration    = $entry.End - $entry.Start
                        $entry.Start = $prevEnd + $gapSpan
                        $entry.End   = $entry.Start + $duration
                        $repaired.Add($entry)
                        $prevEnd = $entry.End
                    }
                    'Drop' {
                        # Skip this entry entirely
                        Write-SubtitleLog -Message "Dropped overlapping entry $($entry.Index)." -Level Warning
                        continue
                    }
                }
            } else {
                $repaired.Add($entry)
                $prevEnd = $entry.End
            }
        }

        $InputObject.Entries = $repaired.ToArray()

        # Re-index
        $i = 1
        foreach ($e in $InputObject.Entries) { $e.Index = $i++ }

        return $InputObject
    }
}
