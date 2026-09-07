function Protect-ApiKey {
    <#
    .SYNOPSIS
        Encrypts a plain-text API key using Windows DPAPI (CurrentUser scope).
    .OUTPUTS
        Base64-encoded encrypted string.
    #>
    param([Parameter(Mandatory)][string] $PlainText)

    if (-not ((-not (Test-Path Variable:\IsWindows)) -or $IsWindows)) {
        throw 'Storing translation provider API keys requires Windows: encrypted credential storage uses the Windows Data Protection API (DPAPI), which is not available on this platform.'
    }

    Add-Type -AssemblyName System.Security
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    return [Convert]::ToBase64String($encrypted)
}

function Unprotect-ApiKey {
    <#
    .SYNOPSIS
        Decrypts a DPAPI-encrypted base64 API key back to plain text.
    #>
    param([Parameter(Mandatory)][string] $EncryptedBase64)

    if (-not ((-not (Test-Path Variable:\IsWindows)) -or $IsWindows)) {
        throw 'Reading translation provider API keys requires Windows: encrypted credential storage uses the Windows Data Protection API (DPAPI), which is not available on this platform.'
    }

    Add-Type -AssemblyName System.Security
    $bytes     = [Convert]::FromBase64String($EncryptedBase64)
    $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, 'CurrentUser')
    return [System.Text.Encoding]::UTF8.GetString($decrypted)
}

function Save-ProviderStore {
    <#
    .SYNOPSIS
        Persists $script:ConfiguredProviders and $script:DefaultProvider to disk.
    #>
    $dir = Split-Path $script:ProvidersFilePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $providersObj = @{}
    foreach ($name in $script:ConfiguredProviders.Keys) {
        $p = $script:ConfiguredProviders[$name]
        $providersObj[$name] = @{
            Name              = $p.Name
            Model             = $p.Model
            BaseUrl           = $p.BaseUrl
            RateLimitRpm      = $p.RateLimitRpm
            MaxTokensPerBatch  = $p.MaxTokensPerBatch
            MaxEntriesPerBatch = $p.MaxEntriesPerBatch
            MaxOutputTokens    = $p.MaxOutputTokens
            Temperature       = $p.Temperature
            ApiKeyEncrypted   = $p.ApiKeyEncrypted
        }
    }

    @{
        DefaultProvider = $script:DefaultProvider
        Providers       = $providersObj
    } | ConvertTo-Json -Depth 5 | Set-Content $script:ProvidersFilePath -Encoding UTF8
}
