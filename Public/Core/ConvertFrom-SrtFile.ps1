function ConvertFrom-SrtFile {
    <#
    .SYNOPSIS
        Parses SRT content (string or file path) into an array of SrtEntry objects.
    .PARAMETER Path
        Path to an SRT file.
    .PARAMETER Content
        Raw SRT text content.
    .EXAMPLE
        $entries = ConvertFrom-SrtFile -Path 'movie.srt'
    .EXAMPLE
        $entries = Get-Content 'movie.srt' -Raw | ConvertFrom-SrtFile
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('SrtEntry[]')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string] $Path,

        [Parameter(Mandatory, ParameterSetName = 'Content', ValueFromPipeline)]
        [string] $Content
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $enc     = Get-FileEncoding -Path (Resolve-Path $Path)
            $bytes   = [System.IO.File]::ReadAllBytes($Path)
            $Content = $enc.Encoding.GetString($bytes)
        }

        $warnings = @{}
        $entries  = Invoke-SrtParser -Content $Content -Warnings $warnings

        foreach ($w in $warnings.Values) {
            Write-Warning $w
        }

        return $entries
    }
}
