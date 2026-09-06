function Convert-AssToSrt {
    <#
    .SYNOPSIS
        Converts an ASS/SSA SubtitleFile to SRT format.
    .DESCRIPTION
        Strips all ASS override tags and converts the entries to SrtEntry objects.
        ASS line-break tokens (\N, \n) become real line breaks in the SRT output.
        HTML-style tags (<b>, <i>) in ASS text are preserved as SRT HTML tags.
    .PARAMETER InputObject
        A SubtitleFile with Format 'ASS' or 'SSA'.
    .PARAMETER StripFormatting
        Remove all formatting tags (both ASS override tags and HTML tags).
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Convert-AssToSrt | Export-SubtitleFile -Path 'anime.srt'
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Convert-AssToSrt -StripFormatting
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [switch] $StripFormatting
    )

    process {
        $srtFile         = [SubtitleFile]::new()
        $srtFile.Format  = 'SRT'
        $srtFile.Encoding = 'UTF-8'
        $srtFile.Path    = $InputObject.Path -replace '\.(ass|ssa)$', '.srt'

        $i = 1
        foreach ($entry in $InputObject.Entries) {
            $srt             = [SrtEntry]::new()
            $srt.Index       = $i
            $srt.BlockNumber = $i
            $srt.Start       = $entry.Start
            $srt.End         = $entry.End

            $text = $entry.RawText

            # Convert ASS override tags to SRT HTML where possible, or strip them
            if ($StripFormatting) {
                $text = $text -replace '\{[^}]*\}', ''
            } else {
                # Map common ASS tags to SRT HTML equivalents
                $text = $text -replace '\{\\b1\}',  '<b>'
                $text = $text -replace '\{\\b0\}',  '</b>'
                $text = $text -replace '\{\\i1\}',  '<i>'
                $text = $text -replace '\{\\i0\}',  '</i>'
                $text = $text -replace '\{\\u1\}',  '<u>'
                $text = $text -replace '\{\\u0\}',  '</u>'
                # Strip remaining unmapped tags
                $text = $text -replace '\{[^}]*\}', ''
            }

            # Convert ASS line breaks
            $text = $text -replace '\\N', "`n"
            $text = $text -replace '\\n', "`n"
            $text = $text -replace '\\h', ' '

            $lines         = $text -split "`n"
            $srt.Lines     = $lines
            $srt.RawText   = $lines -join "`n"
            $srt.HasHtmlTags = $text -match '<(b|i|u)\b'

            $srtFile.Entries += $srt
            $i++
        }

        return $srtFile
    }
}
