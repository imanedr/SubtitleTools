function Set-SubtitleLineWidth {
    <#
    .SYNOPSIS
        Wraps long subtitle lines to a maximum character width per line.
    .DESCRIPTION
        After translation, target-language text may be longer than the source.
        This function splits lines that exceed -MaxChars into multiple shorter lines,
        breaking at word boundaries. Useful before export to ensure readability.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER MaxChars
        Maximum characters per line. Default: 42 (standard broadcast spec).
    .PARAMETER MaxLines
        Maximum lines per entry. Lines beyond this limit are joined back.
        Default: 2.
    .EXAMPLE
        $translated | Set-SubtitleLineWidth -MaxChars 42
    .EXAMPLE
        $translated | Set-SubtitleLineWidth -MaxChars 50 -MaxLines 3
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [int] $MaxChars = 42,

        [int] $MaxLines = 2
    )

    process {
        foreach ($entry in $InputObject.Entries) {
            $wrappedLines = [System.Collections.Generic.List[string]]::new()

            foreach ($line in $entry.Lines) {
                if ($line.Length -le $MaxChars) {
                    $wrappedLines.Add($line)
                    continue
                }

                # Wrap at word boundaries
                $words       = $line -split ' '
                $currentLine = ''

                foreach ($word in $words) {
                    $candidate = if ($currentLine) { "$currentLine $word" } else { $word }

                    if ($candidate.Length -le $MaxChars) {
                        $currentLine = $candidate
                    } else {
                        if ($currentLine) { $wrappedLines.Add($currentLine) }
                        $currentLine = $word
                    }
                }

                if ($currentLine) { $wrappedLines.Add($currentLine) }
            }

            # Enforce MaxLines â€” if we have more, join excess back onto last allowed line
            if ($wrappedLines.Count -gt $MaxLines) {
                $kept  = [System.Collections.Generic.List[string]]::new($wrappedLines.GetRange(0, $MaxLines - 1))
                $extra = $wrappedLines.GetRange($MaxLines - 1, $wrappedLines.Count - ($MaxLines - 1))
                $kept.Add($extra -join ' ')
                $wrappedLines = $kept
            }

            $entry.Lines   = $wrappedLines.ToArray()
            $entry.RawText = $entry.Lines -join "`n"
        }

        return $InputObject
    }
}
