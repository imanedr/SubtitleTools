function Set-SubDLCredential {
    <#
    .SYNOPSIS
        Stores a SubDL authentication token encrypted with Windows DPAPI.
    .DESCRIPTION
        Encrypts the token using DPAPI (CurrentUser scope) and persists it to
        %APPDATA%\SubtitleTools\subdl.json. The token is required by
        Publish-SubtitleFile to authenticate with the SubDL Upload API.

        Obtain the JWT token from subdl.com by signing in, then opening the browser
        Developer Tools (F12) > Network tab, triggering any API call, and copying
        the value of the 'authorization' request header (without the 'Bearer ' prefix).
    .PARAMETER Token
        SubDL authentication token as plain text. Encrypted immediately; the
        plain-text value is not stored.
    .PARAMETER TokenSecure
        SubDL authentication token as a SecureString.
    .EXAMPLE
        Set-SubDLCredential -Token 'your-subdl-token-here'
    .EXAMPLE
        $secure = Read-Host 'SubDL token' -AsSecureString
        Set-SubDLCredential -TokenSecure $secure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'PlainText')]
        [string] $Token,

        [Parameter(Mandatory, ParameterSetName = 'Secure')]
        [SecureString] $TokenSecure
    )

    $plainText = if ($PSCmdlet.ParameterSetName -eq 'Secure') {
        [System.Net.NetworkCredential]::new('', $TokenSecure).Password
    } else {
        $Token
    }

    $script:SubDLTokenEncrypted = Protect-SubDLToken -PlainText $plainText
    Save-SubDLTokenStore

    Write-Verbose 'SubDL token saved.'
}
