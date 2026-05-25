function New-TranslationSession {
    <#
    .SYNOPSIS
        Creates a translation session object for batch translation runs.
    .DESCRIPTION
        A session holds the provider config, optional glossary, and a content-hash
        cache to avoid re-translating unchanged entries across multiple calls.
        Pass the session to Invoke-SubtitleTranslation via -Session.
    .PARAMETER ProviderName
        The provider to use for this session.
    .PARAMETER GlossaryPath
        Path to a JSON glossary file: { "source_term": "target_term", ... }
    .PARAMETER CheckpointPath
        Path to a checkpoint file for resume support (-ResumeFrom).
    .EXAMPLE
        $session = New-TranslationSession -ProviderName Anthropic -GlossaryPath './glossary.json'
        Invoke-SubtitleTranslation -Path 'movie.srt' -TargetLanguage 'fa' -Session $session
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $ProviderName,

        [string] $GlossaryPath,

        [string] $CheckpointPath
    )

    if (-not $script:ConfiguredProviders.ContainsKey($ProviderName)) {
        throw "Provider '$ProviderName' is not configured. Run Set-TranslationProvider first."
    }

    $glossary = @{}
    if ($GlossaryPath -and (Test-Path $GlossaryPath)) {
        $glossary = Get-Content $GlossaryPath -Raw | ConvertFrom-Json -AsHashtable
    }

    $cache = @{}
    if ($CheckpointPath -and (Test-Path $CheckpointPath)) {
        $cache = Get-Content $CheckpointPath -Raw | ConvertFrom-Json -AsHashtable
        Write-Verbose "Loaded $($cache.Count) cached translations from '$CheckpointPath'."
    }

    return @{
        Provider        = $script:ConfiguredProviders[$ProviderName]
        Glossary        = $glossary
        Cache           = $cache
        CheckpointPath  = $CheckpointPath
        RequestCount    = 0
        WindowStart     = [datetime]::UtcNow
        ContentContext  = $null
    }
}
