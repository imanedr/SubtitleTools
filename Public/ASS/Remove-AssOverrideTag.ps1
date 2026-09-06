function Remove-AssOverrideTag {
    <#
    .SYNOPSIS
        Strips ASS override tags ({\...}) from subtitle entry text.
    .DESCRIPTION
        Removes all or specific override tags from entry text. Useful when you want
        clean text for translation or plain-text export.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER TagPattern
        Regex pattern to match specific tags to remove. Default: removes all tags.
        Example: '\\i[01]' removes only italic on/off tags.
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Remove-AssOverrideTag
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Remove-AssOverrideTag -TagPattern '\\pos\([^)]+\)'
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [string] $TagPattern = '[^}]*'
    )

    process {
        $fullPattern = '\{' + $TagPattern + '\}'

        foreach ($entry in $InputObject.Entries) {
            $cleanLines = $entry.Lines | ForEach-Object {
                $_ -replace $fullPattern, ''
            }
            $entry.Lines   = $cleanLines
            $entry.RawText = $cleanLines -join [System.Environment]::NewLine

            if ($entry -is [AssEntry]) {
                $entry.OverrideTags = @()
            }
        }

        return $InputObject
    }
}
