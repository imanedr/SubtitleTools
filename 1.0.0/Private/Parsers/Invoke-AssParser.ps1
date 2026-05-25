function Invoke-AssParser {
    <#
    .SYNOPSIS
        Parses ASS/SSA text content into a SubtitleFile object.
    .OUTPUTS
        SubtitleFile
    #>
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory)]
        [string] $Content,

        [hashtable] $Warnings = @{}
    )

    $normalized = ConvertTo-NormalizedText -Text $Content
    $lines      = $normalized -split '\n'

    $file           = [SubtitleFile]::new()
    $file.Format    = 'ASS'
    $file.Header    = [AssHeader]::new()

    $currentSection  = ''
    $eventColumns    = @()
    $dialogueIndex   = 1

    foreach ($line in $lines) {
        $trimmed = $line.Trim()

        # Section headers
        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $Matches[1].ToLower()

            if ($currentSection -eq 'v4 styles' -or $currentSection -eq 'v4+ styles') {
                $file.Header.ScriptType = if ($currentSection -like '*+*') { 'v4.00+' } else { 'v4.00' }
                $file.Format = if ($currentSection -like '*+*') { 'ASS' } else { 'SSA' }
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) { continue }

        switch -Regex ($currentSection) {
            'script info' {
                if ($trimmed -match '^(.+?):\s*(.*)$') {
                    $key   = $Matches[1].Trim()
                    $value = $Matches[2].Trim()
                    switch ($key) {
                        'ScriptType'     { $file.Header.ScriptType   = $value }
                        'Title'          { $file.Header.Title         = $value }
                        'Original Script' { $file.Header.OriginalScript = $value }
                        'PlayResX'       { $file.Header.PlayResX      = $value }
                        'PlayResY'       { $file.Header.PlayResY      = $value }
                        'YCbCr Matrix'   { $file.Header.YCbCrMatrix   = $value }
                        default          { $file.Header.ExtraFields[$key] = $value }
                    }
                }
            }

            '(v4\+? styles|v4 styles)' {
                if ($trimmed -match '^Format:\s*(.+)$') {
                    # Store style column order (not used for parsing but preserved for output)
                } elseif ($trimmed -match '^Style:\s*(.+)$') {
                    $styleLine = $Matches[1]
                    $parts     = $styleLine -split ','

                    if ($parts.Count -ge 23) {
                        $style                  = [AssStyle]::new()
                        $style.Name             = $parts[0].Trim()
                        $style.Fontname         = $parts[1].Trim()
                        $style.Fontsize         = [int]($parts[2].Trim() -replace '[^\d]', '')
                        $style.PrimaryColour    = $parts[3].Trim()
                        $style.SecondaryColour  = $parts[4].Trim()
                        $style.OutlineColour    = $parts[5].Trim()
                        $style.BackColour       = $parts[6].Trim()
                        $style.Bold             = $parts[7].Trim() -eq '-1'
                        $style.Italic           = $parts[8].Trim() -eq '-1'
                        $style.Underline        = $parts[9].Trim() -eq '-1'
                        $style.StrikeOut        = $parts[10].Trim() -eq '-1'
                        $style.ScaleX           = [decimal]($parts[11].Trim())
                        $style.ScaleY           = [decimal]($parts[12].Trim())
                        $style.Spacing          = [decimal]($parts[13].Trim())
                        $style.Angle            = [decimal]($parts[14].Trim())
                        $style.BorderStyle      = [int]($parts[15].Trim())
                        $style.Outline          = [decimal]($parts[16].Trim())
                        $style.Shadow           = [decimal]($parts[17].Trim())
                        $style.Alignment        = [int]($parts[18].Trim())
                        $style.MarginL          = [int]($parts[19].Trim())
                        $style.MarginR          = [int]($parts[20].Trim())
                        $style.MarginV          = [int]($parts[21].Trim())
                        $style.Encoding         = [int]($parts[22].Trim())

                        $file.Header.Styles += $style
                    } else {
                        $Warnings[$dialogueIndex] = "Style line has fewer than 23 fields: '$trimmed'"
                    }
                }
            }

            'events' {
                if ($trimmed -match '^Format:\s*(.+)$') {
                    $eventColumns                   = ($Matches[1] -split ',') | ForEach-Object { $_.Trim() }
                    $file.Header.EventColumnOrder   = $eventColumns
                } elseif ($trimmed -match '^(Dialogue|Comment):\s*(.+)$') {
                    $eventType  = $Matches[1]
                    $eventData  = $Matches[2]

                    # Split on commas but only up to the number of columns minus 1
                    # (Text field may contain commas)
                    $maxSplit   = $eventColumns.Count
                    $parts      = $eventData -split ',', $maxSplit

                    if ($parts.Count -lt $maxSplit) {
                        $Warnings[$dialogueIndex] = "Event line has fewer fields than Format line: '$trimmed'"
                        continue
                    }

                    # Map columns by position
                    $colMap = @{}
                    for ($i = 0; $i -lt $eventColumns.Count; $i++) {
                        $colMap[$eventColumns[$i]] = if ($i -lt $parts.Count) { $parts[$i].Trim() } else { '' }
                    }

                    # Text column may have trailing parts if we had extra commas â€” join them back
                    $textColIndex = $eventColumns.IndexOf('Text')
                    if ($textColIndex -ge 0 -and $parts.Count -gt $textColIndex) {
                        $colMap['Text'] = ($parts[$textColIndex..($parts.Count - 1)]) -join ','
                    }

                    $entry           = [AssEntry]::new()
                    $entry.Index     = $dialogueIndex
                    $entry.EventType = $eventType

                    try {
                        $entry.Start = ConvertFrom-AssTimestamp -Timestamp $colMap['Start']
                        $entry.End   = ConvertFrom-AssTimestamp -Timestamp $colMap['End']
                    } catch {
                        $Warnings[$dialogueIndex] = "Entry $dialogueIndex timestamp parse failed: $($_.Exception.Message)"
                        $dialogueIndex++
                        continue
                    }

                    $entry.Layer   = $colMap['Layer']
                    $entry.Style   = $colMap['Style']
                    $entry.Name    = $colMap['Name']
                    $entry.MarginL = $colMap['MarginL']
                    $entry.MarginR = $colMap['MarginR']
                    $entry.MarginV = $colMap['MarginV']
                    $entry.Effect  = $colMap['Effect']

                    $rawText         = $colMap['Text']
                    $entry.RawText   = $rawText

                    # Extract override tags, then get plain lines
                    $plainText       = $rawText -replace '\{[^}]*\}', ''
                    $overrideTags    = [regex]::Matches($rawText, '\{[^}]*\}') | ForEach-Object { $_.Value }
                    $entry.OverrideTags = $overrideTags
                    $entry.Lines     = ($plainText -replace '\\N', "`n") -split "`n"

                    # Only add Dialogue entries to the entries array
                    # Comment entries are stored in metadata
                    if ($eventType -eq 'Dialogue') {
                        $file.Entries += $entry
                    }

                    $dialogueIndex++
                }
            }
        }
    }

    $file.ParserWarnings = $Warnings
    return $file
}
