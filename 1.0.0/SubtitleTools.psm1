#Requires -Version 5.1

# ============================================================
# CLASS DEFINITIONS
# Must be defined directly in the root psm1 — NOT dot-sourced.
# PowerShell 5.1 classes in dot-sourced files are not accessible
# to callers that use Import-Module (only 'using module' would work).
# ============================================================

class SubtitleEntry {
    [int]       $Index
    [TimeSpan]  $Start
    [TimeSpan]  $End
    [string[]]  $Lines
    [string]    $RawText
    [hashtable] $Metadata

    SubtitleEntry() {
        $this.Metadata = @{}
        $this.Lines    = @()
    }

    [TimeSpan] Duration() { return $this.End - $this.Start }
    [string]   Text()     { return $this.Lines -join "`n" }

    [string] ToString() {
        return '[{0}] {1} --> {2} : {3}' -f $this.Index, $this.Start, $this.End, ($this.Lines -join ' ')
    }
}

class SrtEntry : SubtitleEntry {
    [int]  $BlockNumber
    [bool] $HasHtmlTags

    SrtEntry() : base() { $this.HasHtmlTags = $false }
}

class AssEntry : SubtitleEntry {
    [string]   $Layer
    [string]   $Style
    [string]   $Name
    [string]   $MarginL
    [string]   $MarginR
    [string]   $MarginV
    [string]   $Effect
    [string]   $EventType
    [string[]] $OverrideTags

    AssEntry() : base() {
        $this.Layer        = '0'
        $this.Style        = 'Default'
        $this.Name         = ''
        $this.MarginL      = '0000'
        $this.MarginR      = '0000'
        $this.MarginV      = '0000'
        $this.Effect       = ''
        $this.EventType    = 'Dialogue'
        $this.OverrideTags = @()
    }
}

class AssStyle {
    [string]  $Name
    [string]  $Fontname
    [int]     $Fontsize
    [string]  $PrimaryColour
    [string]  $SecondaryColour
    [string]  $OutlineColour
    [string]  $BackColour
    [bool]    $Bold
    [bool]    $Italic
    [bool]    $Underline
    [bool]    $StrikeOut
    [decimal] $ScaleX
    [decimal] $ScaleY
    [decimal] $Spacing
    [decimal] $Angle
    [int]     $BorderStyle
    [decimal] $Outline
    [decimal] $Shadow
    [int]     $Alignment
    [int]     $MarginL
    [int]     $MarginR
    [int]     $MarginV
    [int]     $Encoding

    AssStyle() {
        $this.Name            = 'Default'
        $this.Fontname        = 'Arial'
        $this.Fontsize        = 20
        $this.PrimaryColour   = '&H00FFFFFF&'
        $this.SecondaryColour = '&H000000FF&'
        $this.OutlineColour   = '&H00000000&'
        $this.BackColour      = '&H00000000&'
        $this.Bold            = $false
        $this.Italic          = $false
        $this.Underline       = $false
        $this.StrikeOut       = $false
        $this.ScaleX          = 100
        $this.ScaleY          = 100
        $this.Spacing         = 0
        $this.Angle           = 0
        $this.BorderStyle     = 1
        $this.Outline         = 2
        $this.Shadow          = 0
        $this.Alignment       = 2
        $this.MarginL         = 10
        $this.MarginR         = 10
        $this.MarginV         = 10
        $this.Encoding        = 1
    }

    [string] ToAssLine() {
        $b = if ($this.Bold)      { '-1' } else { '0' }
        $i = if ($this.Italic)    { '-1' } else { '0' }
        $u = if ($this.Underline) { '-1' } else { '0' }
        $s = if ($this.StrikeOut) { '-1' } else { '0' }
        return 'Style: {0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17},{18},{19},{20},{21},{22}' -f `
            $this.Name, $this.Fontname, $this.Fontsize,
            $this.PrimaryColour, $this.SecondaryColour, $this.OutlineColour, $this.BackColour,
            $b, $i, $u, $s,
            $this.ScaleX, $this.ScaleY, $this.Spacing, $this.Angle,
            $this.BorderStyle, $this.Outline, $this.Shadow,
            $this.Alignment, $this.MarginL, $this.MarginR, $this.MarginV, $this.Encoding
    }
}

class AssHeader {
    [string]     $ScriptType
    [string]     $Title
    [string]     $OriginalScript
    [string]     $PlayResX
    [string]     $PlayResY
    [string]     $YCbCrMatrix
    [hashtable]  $ExtraFields
    [AssStyle[]] $Styles
    [string[]]   $EventColumnOrder

    AssHeader() {
        $this.ScriptType       = 'v4.00+'
        $this.Title            = 'Untitled'
        $this.OriginalScript   = ''
        $this.PlayResX         = '640'
        $this.PlayResY         = '480'
        $this.YCbCrMatrix      = ''
        $this.ExtraFields      = @{}
        $this.Styles           = @()
        $this.EventColumnOrder = @('Layer','Start','End','Style','Name','MarginL','MarginR','MarginV','Effect','Text')
    }
}

class SubtitleFile {
    [string]          $Path
    [string]          $Format
    [string]          $Encoding
    [bool]            $HasBom
    [AssHeader]       $Header
    [SubtitleEntry[]] $Entries
    [hashtable]       $ParserWarnings

    SubtitleFile() {
        $this.Entries        = @()
        $this.ParserWarnings = @{}
        $this.HasBom         = $false
        $this.Encoding       = 'UTF-8'
    }

    [int]      EntryCount()    { return $this.Entries.Count }
    [TimeSpan] TotalDuration() {
        if ($this.Entries.Count -eq 0) { return [TimeSpan]::Zero }
        return ($this.Entries | Sort-Object End | Select-Object -Last 1).End
    }
    [string] ToString() {
        return '[SubtitleFile] Format={0} Entries={1} Path={2}' -f $this.Format, $this.Entries.Count, $this.Path
    }
}

class ValidationIssue {
    [int]    $EntryIndex
    [string] $Field
    [string] $Message
    [string] $Severity

    ValidationIssue([int]$index, [string]$field, [string]$message, [string]$severity) {
        $this.EntryIndex = $index
        $this.Field      = $field
        $this.Message    = $message
        $this.Severity   = $severity
    }
    [string] ToString() {
        return '[{0}] Entry {1} {2}: {3}' -f $this.Severity, $this.EntryIndex, $this.Field, $this.Message
    }
}

class ValidationResult {
    [bool]              $IsValid
    [string]            $FilePath
    [string]            $Format
    [ValidationIssue[]] $Errors
    [ValidationIssue[]] $Warnings
    [int]               $ErrorCount
    [int]               $WarningCount

    ValidationResult() {
        $this.IsValid      = $true
        $this.Errors       = @()
        $this.Warnings     = @()
        $this.ErrorCount   = 0
        $this.WarningCount = 0
    }

    [void] AddError([int]$index, [string]$field, [string]$message) {
        $issue         = [ValidationIssue]::new($index, $field, $message, 'Error')
        $this.Errors  += $issue
        $this.ErrorCount++
        $this.IsValid  = $false
    }

    [void] AddWarning([int]$index, [string]$field, [string]$message) {
        $issue            = [ValidationIssue]::new($index, $field, $message, 'Warning')
        $this.Warnings   += $issue
        $this.WarningCount++
    }

    [string] ToString() {
        $status = if ($this.IsValid) { 'VALID' } else { 'INVALID' }
        return '[ValidationResult] {0} Errors={1} Warnings={2}' -f $status, $this.ErrorCount, $this.WarningCount
    }
}

class TranslationProvider {
    [string]   $Name
    [string]   $Model
    [string]   $ApiKeyEncrypted    # DPAPI-encrypted base64 API key (CurrentUser scope)
    [string]   $BaseUrl
    [int]      $MaxTokensPerBatch
    [int]      $RateLimitRpm       # Requests per minute (0 = unlimited)
    [decimal]  $Temperature
    [string[]] $SupportedLanguages

    TranslationProvider() {
        $this.Temperature        = 0.3
        $this.MaxTokensPerBatch  = 4000
        $this.RateLimitRpm       = 60
        $this.SupportedLanguages = @()
    }

    [string] ToString() {
        return '[TranslationProvider] {0} Model={1}' -f $this.Name, $this.Model
    }
}


# ============================================================
# LOAD PRIVATE FUNCTIONS
# ============================================================
$PrivateFiles = Get-ChildItem -Path "$PSScriptRoot\Private" -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($File in $PrivateFiles) {
    . $File.FullName
}

# ============================================================
# LOAD PUBLIC FUNCTIONS
# ============================================================
$PublicFiles = Get-ChildItem -Path "$PSScriptRoot\Public" -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue

foreach ($File in $PublicFiles) {
    . $File.FullName
}

# Export only public functions
$ExportNames = $PublicFiles | ForEach-Object { $_.BaseName }
Export-ModuleMember -Function $ExportNames

# ============================================================
# LOAD REFERENCE DATA
# ============================================================
$DataPath = "$PSScriptRoot\Data"

if (Test-Path "$DataPath\ProviderDefaults.json") {
    $script:ProviderDefaults = Get-Content "$DataPath\ProviderDefaults.json" -Raw | ConvertFrom-Json
}
if (Test-Path "$DataPath\LanguageCodes.json") {
    $script:LanguageCodes = Get-Content "$DataPath\LanguageCodes.json" -Raw | ConvertFrom-Json
}
if (Test-Path "$DataPath\DefaultAssStyles.json") {
    $script:DefaultAssStyles = Get-Content "$DataPath\DefaultAssStyles.json" -Raw | ConvertFrom-Json
}
if (Test-Path "$DataPath\SubDLLanguages.json") {
    $script:SubDLLanguages = Get-Content "$DataPath\SubDLLanguages.json" -Raw | ConvertFrom-Json
}

# Module-scope storage for configured translation providers
$script:ConfiguredProviders = @{}
$script:DefaultProvider     = $null
$script:ProvidersFilePath   = Join-Path $env:APPDATA 'SubtitleTools\providers.json'

# Module-scope SubDL token store
$script:SubDLTokenEncrypted = $null
$script:SubDLTokenStorePath = Join-Path $env:APPDATA 'SubtitleTools\subdl.json'

# Load persisted providers on module import
if (Test-Path $script:ProvidersFilePath) {
    try {
        $store = Get-Content $script:ProvidersFilePath -Raw | ConvertFrom-Json
        $script:DefaultProvider = $store.DefaultProvider
        foreach ($provName in ($store.Providers | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Name) {
            $p        = $store.Providers.$provName
            $provider = [TranslationProvider]::new()
            $provider.Name              = $p.Name
            $provider.Model             = $p.Model
            $provider.BaseUrl           = $p.BaseUrl
            $provider.RateLimitRpm      = $p.RateLimitRpm
            $provider.MaxTokensPerBatch = $p.MaxTokensPerBatch
            $provider.Temperature       = [decimal]$p.Temperature
            $provider.ApiKeyEncrypted   = $p.ApiKeyEncrypted
            $script:ConfiguredProviders[$provName] = $provider
        }
        Write-Verbose "SubtitleTools: Loaded $($script:ConfiguredProviders.Count) provider(s). Default: $script:DefaultProvider"
    } catch {
        Write-Warning "SubtitleTools: Could not load saved providers: $_"
    }
}

# Load persisted SubDL token on module import
if (Test-Path $script:SubDLTokenStorePath) {
    try {
        $subdlStore = Get-Content $script:SubDLTokenStorePath -Raw | ConvertFrom-Json
        $script:SubDLTokenEncrypted = $subdlStore.TokenEncrypted
        Write-Verbose 'SubtitleTools: SubDL token loaded.'
    } catch {
        Write-Warning "SubtitleTools: Could not load SubDL token: $_"
    }
}

