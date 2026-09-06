function ConvertTo-AssFile {
    <#
    .SYNOPSIS
        Serializes a SubtitleFile to ASS-formatted text.
    .PARAMETER InputObject
        The SubtitleFile object to serialize.
    .EXAMPLE
        $sub | ConvertTo-AssFile | Set-Content output.ass -Encoding UTF8
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        $sb = [System.Text.StringBuilder]::new()

        # Write header (Script Info + Styles)
        if ($InputObject.Header) {
            [void]$sb.Append((Write-AssHeader -Header $InputObject.Header))
        } else {
            # Create a minimal default header
            $defaultHeader = [AssHeader]::new()
            $defaultStyle  = [AssStyle]::new()
            $defaultHeader.Styles = @($defaultStyle)
            [void]$sb.Append((Write-AssHeader -Header $defaultHeader))
        }

        # Events section
        [void]$sb.AppendLine('[Events]')
        [void]$sb.AppendLine('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text')

        foreach ($entry in $InputObject.Entries) {
            if ($entry -is [AssEntry]) {
                [void]$sb.AppendLine((Write-AssEntry -Entry $entry))
            } else {
                # Convert generic SubtitleEntry to AssEntry
                $assEntry           = [AssEntry]::new()
                $assEntry.Index     = $entry.Index
                $assEntry.Start     = $entry.Start
                $assEntry.End       = $entry.End
                $assEntry.Lines     = $entry.Lines
                [void]$sb.AppendLine((Write-AssEntry -Entry $assEntry))
            }
        }

        return $sb.ToString()
    }
}
