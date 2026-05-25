function Remove-SubDLCredential {
    <#
    .SYNOPSIS
        Removes the stored SubDL authentication token.
    .DESCRIPTION
        Clears the in-memory token and deletes %APPDATA%\SubtitleTools\subdl.json.
    .EXAMPLE
        Remove-SubDLCredential
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ([string]::IsNullOrEmpty($script:SubDLTokenEncrypted) -and -not (Test-Path $script:SubDLTokenStorePath)) {
        Write-Warning 'No SubDL token is currently stored.'
        return
    }

    if ($PSCmdlet.ShouldProcess('SubDL token', 'Remove')) {
        $script:SubDLTokenEncrypted = $null

        if (Test-Path $script:SubDLTokenStorePath) {
            Remove-Item $script:SubDLTokenStorePath -Force
        }

        Write-Verbose 'SubDL token removed.'
    }
}
