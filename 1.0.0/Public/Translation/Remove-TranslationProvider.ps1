function Remove-TranslationProvider {
    <#
    .SYNOPSIS
        Removes a saved translation provider and its stored API key.
    .PARAMETER Name
        Provider name to remove: OpenAI, Anthropic, or Google.
    .EXAMPLE
        Remove-TranslationProvider -Name Google
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $Name
    )

    if (-not $script:ConfiguredProviders.ContainsKey($Name)) {
        Write-Warning "Provider '$Name' is not saved."
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Remove translation provider')) {
        $script:ConfiguredProviders.Remove($Name)

        if ($script:DefaultProvider -eq $Name) {
            $script:DefaultProvider = $script:ConfiguredProviders.Keys | Select-Object -First 1
            if ($script:DefaultProvider) {
                Write-Verbose "Default provider changed to '$script:DefaultProvider'."
            }
        }

        Save-ProviderStore
        Write-Host "Provider '$Name' removed."
    }
}
