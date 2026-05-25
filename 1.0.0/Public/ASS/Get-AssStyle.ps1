function Get-AssStyle {
    <#
    .SYNOPSIS
        Retrieves one or all styles from an ASS/SSA SubtitleFile.
    .PARAMETER InputObject
        A SubtitleFile with Format 'ASS' or 'SSA'.
    .PARAMETER Name
        Style name to retrieve. If omitted, returns all styles.
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Get-AssStyle
    .EXAMPLE
        Import-SubtitleFile 'anime.ass' | Get-AssStyle -Name 'Default'
    #>
    [CmdletBinding()]
    [OutputType('AssStyle[]')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [string] $Name
    )

    process {
        if (-not $InputObject.Header) {
            Write-Warning 'SubtitleFile has no Header (not an ASS/SSA file).'
            return
        }

        if ($Name) {
            $InputObject.Header.Styles | Where-Object { $_.Name -eq $Name }
        } else {
            $InputObject.Header.Styles
        }
    }
}
