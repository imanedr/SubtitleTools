function Convert-AssToPlainText {
    <#
    .SYNOPSIS
        Converts ASS subtitle text to plain text by stripping all override tags and
        HTML-style tags, and converting ASS line-break tokens to real line breaks.
    .DESCRIPTION
        Strips: {\...} override tags, <font>, <b>, <i>, <u> HTML tags, and converts
        \N and \n ASS line-break tokens to newlines.
    .PARAMETER InputObject
        A SubtitleFile object.
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Convert-AssToPlainText
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject
    )

    process {
        foreach ($entry in $InputObject.Entries) {
            $cleaned = $entry.RawText

            # Remove ASS override tags
            $cleaned = $cleaned -replace '\{[^}]*\}', ''

            # Convert ASS line-break tokens to newline
            $cleaned = $cleaned -replace '\\N', "`n"
            $cleaned = $cleaned -replace '\\n', "`n"
            $cleaned = $cleaned -replace '\\h', ' '

            # Remove HTML-style tags
            $cleaned = $cleaned -replace '<[^>]+>', ''

            $lines         = $cleaned -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $entry.Lines   = $lines
            $entry.RawText = $lines -join "`n"

            if ($entry -is [AssEntry]) {
                $entry.OverrideTags = @()
            }
        }

        return $InputObject
    }
}
