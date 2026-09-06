function Get-SubDLCredential {
    <#
    .SYNOPSIS
        Shows whether a SubDL authentication token is currently stored.
    .DESCRIPTION
        Returns a summary object indicating whether a token has been saved with
        Set-SubDLCredential. The token itself is never exposed in plain text.
    .EXAMPLE
        Get-SubDLCredential
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [PSCustomObject]@{
        HasToken = (-not [string]::IsNullOrEmpty($script:SubDLTokenEncrypted))
    }
}
