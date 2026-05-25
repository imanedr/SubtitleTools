function ConvertFrom-AssFile {
    <#
    .SYNOPSIS
        Parses ASS/SSA content (string or file path) into a SubtitleFile object.
    .PARAMETER Path
        Path to an ASS or SSA file.
    .PARAMETER Content
        Raw ASS text content.
    .EXAMPLE
        $sub = ConvertFrom-AssFile -Path 'anime.ass'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('SubtitleFile')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Content', ValueFromPipeline)]
        [string] $Content
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $resolvedPath = Resolve-Path -Path $Path | Select-Object -ExpandProperty Path
            $enc          = Get-FileEncoding -Path $resolvedPath
            $bytes        = [System.IO.File]::ReadAllBytes($resolvedPath)
            $Content      = $enc.Encoding.GetString($bytes)
        }

        $warnings = @{}
        $file     = Invoke-AssParser -Content $Content -Warnings $warnings

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file.Path = $resolvedPath
        }

        foreach ($w in $warnings.Values) {
            Write-Warning $w
        }

        return $file
    }
}
