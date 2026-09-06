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

Describe 'TranslationProvider MaxOutputTokens migration' {
    Context 'Loading a v1.0.0-era providers.json with no MaxOutputTokens key' {
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
                        # Intentionally NO MaxOutputTokens key - simulates a
                        # providers.json written before this property existed.
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
    }
}
