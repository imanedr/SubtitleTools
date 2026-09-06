function Convert-SrtToAss {
    <#
    .SYNOPSIS
        Converts an SRT SubtitleFile to ASS format.
    .DESCRIPTION
        Creates a new SubtitleFile with ASS format. SRT HTML tags (<b>, <i>, <u>)
        are mapped to ASS override tags. A default style is applied unless
        -StyleName references an existing style from -TemplateFile.
    .PARAMETER InputObject
        A SubtitleFile with Format 'SRT'.
    .PARAMETER StyleName
        Name for the default style. Default: 'Default'.
    .PARAMETER TemplateFile
        An existing ASS SubtitleFile whose Header/Styles are reused in the output.
    .PARAMETER PlayResX
        Output resolution width. Default: 1280.
    .PARAMETER PlayResY
        Output resolution height. Default: 720.
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Convert-SrtToAss | Export-SubtitleFile -Path 'movie.ass'
    .EXAMPLE
        $template = Import-SubtitleFile 'template.ass'
        Import-SubtitleFile 'movie.srt' | Convert-SrtToAss -TemplateFile $template
    #>
    [CmdletBinding()]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [string] $StyleName    = 'Default',

        [SubtitleFile] $TemplateFile,

        [string] $PlayResX = '1280',
        [string] $PlayResY = '720'
    )

    process {
        $assFile          = [SubtitleFile]::new()
        $assFile.Format   = 'ASS'
        $assFile.Encoding = 'UTF-8'
        $assFile.Path     = $InputObject.Path -replace '\.srt$', '.ass'

        if ($TemplateFile -and $TemplateFile.Header) {
            $assFile.Header = $TemplateFile.Header
        } else {
            $header           = [AssHeader]::new()
            $header.PlayResX  = $PlayResX
            $header.PlayResY  = $PlayResY
            $style            = [AssStyle]::new()
            $style.Name       = $StyleName
            $header.Styles    = @($style)
            $assFile.Header   = $header
        }

        $i = 1
        foreach ($entry in $InputObject.Entries) {
            $assEntry           = [AssEntry]::new()
            $assEntry.Index     = $i
            $assEntry.Start     = $entry.Start
            $assEntry.End       = $entry.End
            $assEntry.Style     = $StyleName
            $assEntry.EventType = 'Dialogue'

            # Convert SRT HTML tags to ASS override tags
            $lines = $entry.Lines | ForEach-Object {
                $line = $_
                $line = $line -replace '<b>',  '{\b1}'
                $line = $line -replace '</b>', '{\b0}'
                $line = $line -replace '<i>',  '{\i1}'
                $line = $line -replace '</i>', '{\i0}'
                $line = $line -replace '<u>',  '{\u1}'
                $line = $line -replace '</u>', '{\u0}'
                # Strip any remaining HTML (e.g. <font color="...">)
                $line = $line -replace '<[^>]+>', ''
                $line
            }

            $assEntry.Lines   = $lines
            $assEntry.RawText = $lines -join '\N'

            $assFile.Entries += $assEntry
            $i++
        }

        return $assFile
    }
}
