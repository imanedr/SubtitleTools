#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path '..' 'SubtitleTools.psd1')

    # Save the current config-root environment so it can be restored after this
    # file's tests re-point the module at a temp providers.json.
    $script:OriginalXdgConfigHome    = $env:XDG_CONFIG_HOME
    $script:OriginalXdgConfigHomeSet = Test-Path Env:\XDG_CONFIG_HOME
}

AfterAll {
    # Restore the original config-root environment and reload the module against
    # it, so later test files (and any interactive session) see normal state.
    if ($script:OriginalXdgConfigHomeSet) {
        $env:XDG_CONFIG_HOME = $script:OriginalXdgConfigHome
    } else {
        Remove-Item Env:\XDG_CONFIG_HOME -ErrorAction SilentlyContinue
    }
    Import-Module $ModulePath -Force
}

Describe 'TranslationProvider settings migration' {
    Context 'Loading a v1.0.0-era providers.json with no MaxOutputTokens/MaxEntriesPerBatch keys' {
        BeforeAll {
            # Point the module's non-Windows config root (XDG_CONFIG_HOME) at a
            # fresh temp directory, and seed a providers.json that predates the
            # MaxOutputTokens property entirely.
            $script:TempConfigRoot = Join-Path ([System.IO.Path]::GetTempPath()) "SubtitleToolsTest_$([Guid]::NewGuid())"
            $subtitleToolsConfigDir = Join-Path $script:TempConfigRoot 'SubtitleTools'
            New-Item -ItemType Directory -Path $subtitleToolsConfigDir -Force | Out-Null

            $legacyStore = @{
                DefaultProvider = 'OpenAI'
                Providers       = @{
                    OpenAI = @{
                        Name              = 'OpenAI'
                        Model             = 'gpt-4o'
                        BaseUrl           = 'https://api.openai.com/v1'
                        RateLimitRpm      = 60
                        MaxTokensPerBatch = 4000
                        Temperature       = 0.3
                        ApiKeyEncrypted   = 'not-a-real-key'
                        # Intentionally NO MaxOutputTokens / MaxEntriesPerBatch keys -
                        # simulates a providers.json written before those properties
                        # existed. [int]$null is 0, and 0 would mean "no output tokens"
                        # / "no entries per batch", so both need an explicit guard.
                    }
                }
            }
            $legacyStore | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $subtitleToolsConfigDir 'providers.json') -Encoding UTF8

            $env:XDG_CONFIG_HOME = $script:TempConfigRoot
            Import-Module $ModulePath -Force
        }

        AfterAll {
            Remove-Item -Path $script:TempConfigRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'Defaults the rehydrated provider MaxOutputTokens to 8192, not 0' {
            $provider = Get-TranslationProvider -Name OpenAI
            $provider | Should -Not -BeNullOrEmpty
            $provider.MaxOutputTokens | Should -Be 8192
            $provider.MaxOutputTokens | Should -Not -Be 0
        }

        It 'Defaults the rehydrated provider MaxEntriesPerBatch to 40, not 0' {
            # A 0 here would make the batch planner flush after every single entry,
            # i.e. one API call per subtitle line.
            $provider = Get-TranslationProvider -Name OpenAI
            $provider.MaxEntriesPerBatch | Should -Be 40
            $provider.MaxEntriesPerBatch | Should -Not -Be 0
        }

        It 'Defaults the rehydrated provider ReasoningEffort to auto' {
            $provider = Get-TranslationProvider -Name OpenAI
            $provider.ReasoningEffort | Should -Be 'auto'
        }
    }
}
