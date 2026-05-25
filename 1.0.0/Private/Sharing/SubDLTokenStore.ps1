function Protect-SubDLToken {
    <#
    .SYNOPSIS
        Encrypts a plain-text SubDL token using Windows DPAPI (CurrentUser scope).
    .OUTPUTS
        Base64-encoded encrypted string.
    #>
    param([Parameter(Mandatory)][string] $PlainText)

    Add-Type -AssemblyName System.Security
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    return [Convert]::ToBase64String($encrypted)
}

function Unprotect-SubDLToken {
    <#
    .SYNOPSIS
        Decrypts a DPAPI-encrypted base64 SubDL token back to plain text.
    #>
    param([Parameter(Mandatory)][string] $EncryptedBase64)

    Add-Type -AssemblyName System.Security
    $bytes     = [Convert]::FromBase64String($EncryptedBase64)
    $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, 'CurrentUser')
    return [System.Text.Encoding]::UTF8.GetString($decrypted)
}

function Save-SubDLTokenStore {
    <#
    .SYNOPSIS
        Persists $script:SubDLTokenEncrypted to disk.
    #>
    $dir = Split-Path $script:SubDLTokenStorePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    @{ TokenEncrypted = $script:SubDLTokenEncrypted } |
        ConvertTo-Json | Set-Content $script:SubDLTokenStorePath -Encoding UTF8
}
