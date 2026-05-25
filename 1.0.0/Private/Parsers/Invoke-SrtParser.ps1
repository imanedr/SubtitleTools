function Invoke-SrtParser {
    <#
    .SYNOPSIS
        Parses SRT text content into an array of SrtEntry objects.
    .OUTPUTS
        SrtEntry[]
    #>
    [OutputType('SrtEntry[]')]
    param(
        [Parameter(Mandatory)]
        [string] $Content,

        [hashtable] $Warnings = @{}
    )

    $normalized = ConvertTo-NormalizedText -Text $Content
    $entries    = [System.Collections.Generic.List[SrtEntry]]::new()

    # Split on blank lines between blocks (two or more newlines)
    $blocks = $normalized -split '\n{2,}'

    $index = 1
    foreach ($block in $blocks) {
        $block = $block.Trim()
        if ([string]::IsNullOrWhiteSpace($block)) { continue }

        $lines = $block -split '\n'
        if ($lines.Count -lt 2) {
            $Warnings[$index] = "Block ${index} has fewer than 2 lines, skipping."
            continue
        }

        $entry       = [SrtEntry]::new()
        $entry.Index = $index

        # Line 0: block number (may be missing or out of order)
        $numberLine = $lines[0].Trim()
        if ($numberLine -match '^\d+$') {
            $entry.BlockNumber = [int]$numberLine
            $timeLineIndex     = 1
        } else {
            # No number line -- try treating first line as timestamp
            $Warnings[$index] = "Block ${index} is missing a sequence number."
            $entry.BlockNumber = $index
            $timeLineIndex     = 0
        }

        if ($timeLineIndex -ge $lines.Count) {
            $Warnings[$index] = "Block ${index} has no timestamp line."
            continue
        }

        # Timestamp line: HH:mm:ss,fff --> HH:mm:ss,fff
        $timeLine = $lines[$timeLineIndex].Trim()
        if ($timeLine -match '(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})') {
            try {
                $entry.Start = ConvertFrom-SrtTimestamp -Timestamp $Matches[1]
                $entry.End   = ConvertFrom-SrtTimestamp -Timestamp $Matches[2]
            } catch {
                $msg = $_.Exception.Message
                $Warnings[$index] = "Block ${index} timestamp parse failed: $msg"
                continue
            }

            # Flag if dot separator was used instead of comma
            if ($timeLine -match '\d{2}:\d{2}:\d{2}\.') {
                $Warnings[$index] = "Block ${index} uses dot separator instead of comma in timestamp."
            }
        } else {
            $Warnings[$index] = "Block ${index} has invalid timestamp line: $timeLine"
            continue
        }

        # Remaining lines are subtitle text
        $textLines     = $lines[($timeLineIndex + 1)..($lines.Count - 1)] | ForEach-Object { $_.TrimEnd() }
        $entry.Lines   = $textLines
        $entry.RawText = $textLines -join [System.Environment]::NewLine

        # Detect HTML tags
        if ($entry.RawText -match '<(b|i|u|font)\b') {
            $entry.HasHtmlTags = $true
        }

        $entries.Add($entry)
        $index++
    }

    return $entries.ToArray()
}
