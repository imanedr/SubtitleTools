function ConvertTo-SrtFile {
    <#
    .SYNOPSIS
        Serializes a SubtitleFile or SrtEntry array to SRT-formatted text.
    .PARAMETER InputObject
        A SubtitleFile or array of SrtEntry objects.
    .EXAMPLE
        $sub | ConvertTo-SrtFile | Set-Content output.srt -Encoding UTF8
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )

    process {
        $entries = if ($InputObject -is [SubtitleFile]) {
            $InputObject.Entries
        } else {
            $InputObject
        }

        $sb = [System.Text.StringBuilder]::new()

        $i = 1
        foreach ($entry in $entries) {
            # Build an SrtEntry from a generic SubtitleEntry if needed
            if ($entry -isnot [SrtEntry]) {
                $srt             = [SrtEntry]::new()
                $srt.Index       = $i
                $srt.BlockNumber = $i
                $srt.Start       = $entry.Start
                $srt.End         = $entry.End
                $srt.Lines       = $entry.Lines
                $entry           = $srt
            } else {
                $entry.Index = $i
            }

            [void]$sb.Append((Write-SrtEntry -Entry $entry))
            [void]$sb.AppendLine()  # blank line between blocks
            $i++
        }

        return $sb.ToString().TrimEnd()
    }
}
