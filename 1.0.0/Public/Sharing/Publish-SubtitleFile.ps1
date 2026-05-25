function Publish-SubtitleFile {
    <#
    .SYNOPSIS
        Uploads a subtitle file to SubDL.
    .DESCRIPTION
        Authenticates with SubDL using a stored token and uploads the subtitle
        via their three-step Upload API. The token must be saved first with
        Set-SubDLCredential.

        Accepts a SubtitleFile object (from Import-SubtitleFile or the translation
        pipeline) or a path string. When given an in-memory SubtitleFile whose
        source file no longer exists on disk, the content is serialized to a
        temporary file for upload and cleaned up automatically.

        Returns a result object:
            Success  — $true / $false
            Message  — status message from the API

    .PARAMETER InputObject
        A SubtitleFile object or a string path to a subtitle file.
    .PARAMETER Name
        Display name for the subtitle (required by the SubDL API).
    .PARAMETER Type
        Content type: 'movie' or 'tv'.
    .PARAMETER Language
        Uppercase ISO 639-1 language code (e.g. 'EN', 'FA', 'RU').
        See https://subdl.com/api-files/language_list.json for supported codes.
    .PARAMETER TmdbId
        TMDB ID of the movie or TV show (recommended). At least one of TmdbId
        or ImdbId is required.
    .PARAMETER ImdbId
        IMDB ID of the movie or TV show. At least one of TmdbId or ImdbId
        is required.
    .PARAMETER Quality
        Source quality: 'web' (default), 'bluray', 'dvd', 'hdtv', or 'cam'.
    .PARAMETER ProductionType
        0 = Default, 1 = Translation, 2 = Original, 3 = Machine translated.
        Default: 0.
    .PARAMETER Releases
        Array of release names this subtitle is compatible with.
    .PARAMETER Framerate
        Frame rate the subtitle is synchronized to (0 = default/unspecified).
        Use 2 for 23.976, 3 for 25.000, 4 for 29.970, etc.
    .PARAMETER Comment
        Optional notes about the subtitle.
    .PARAMETER Season
        Season number for TV shows. Use 0 for movies (default: 0).
    .PARAMETER HearingImpaired
        Mark the subtitle as hearing-impaired / SDH.
    .PARAMETER FullSeason
        Mark the subtitle as covering a full season.
    .PARAMETER Tags
        Optional tags to improve searchability.
    .PARAMETER EpisodeFrom
        First episode number this subtitle covers (TV series only).
    .PARAMETER EpisodeTo
        Last episode number this subtitle covers (TV series only).
    .PARAMETER SdId
        SubDL subtitle ID — provide when updating an existing subtitle.
    .PARAMETER PassThru
        Emit InputObject back to the pipeline after publishing, allowing
        further pipeline stages after this function.
    .EXAMPLE
        Publish-SubtitleFile -InputObject 'movie.fa.srt' `
            -Name 'Inception Persian' -Type movie `
            -TmdbId '27205' -Language 'FA'
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' |
            Invoke-SubtitleTranslation -ProviderName Anthropic -TargetLanguage 'fa' |
            Export-SubtitleFile -Path 'movie.fa.srt' |
            Publish-SubtitleFile -Name 'Inception FA' -Type movie -TmdbId '27205' `
                -Language 'FA' -Quality bluray -ProductionType 1 -PassThru
    .EXAMPLE
        Publish-SubtitleFile -InputObject 'show.s01e01.en.srt' `
            -Name 'Breaking Bad S01E01 EN' -Type tv `
            -TmdbId '1396' -Language 'EN' -Season 1 -EpisodeFrom 1 -EpisodeTo 1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('movie', 'tv')]
        [string] $Type,

        [Parameter(Mandatory)]
        [string] $Language,

        [string] $TmdbId,
        [string] $ImdbId,

        [ValidateSet('web', 'bluray', 'dvd', 'hdtv', 'cam')]
        [string] $Quality = 'web',

        [ValidateRange(0, 3)]
        [int] $ProductionType = 0,

        [string[]] $Releases = @(),
        [int]      $Framerate = 0,
        [string]   $Comment = '',
        [int]      $Season = 0,
        [switch]   $HearingImpaired,
        [switch]   $FullSeason,
        [string[]] $Tags = @(),
        [int]      $EpisodeFrom = 0,
        [int]      $EpisodeTo = 0,
        [string]   $SdId,
        [switch]   $PassThru
    )

    process {
        # Validate that at least one content identifier was supplied
        if (-not $TmdbId -and -not $ImdbId) {
            Write-Error 'At least one of -TmdbId or -ImdbId is required.'
            return
        }

        # Validate token is configured
        if ([string]::IsNullOrEmpty($script:SubDLTokenEncrypted)) {
            Write-Error "No SubDL token configured. Run: Set-SubDLCredential -Token 'your-token'"
            return
        }

        # Resolve file path from SubtitleFile object or string
        $tempFile = $null
        $filePath = $null

        if ($InputObject -is [SubtitleFile]) {
            if ($InputObject.Path -and (Test-Path $InputObject.Path)) {
                $filePath = $InputObject.Path
            } else {
                $ext      = if ($InputObject.Format -eq 'ASS') { '.ass' } else { '.srt' }
                $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N') + $ext)
                Export-SubtitleFile -InputObject $InputObject -Path $tempFile
                $filePath = $tempFile
            }
        } elseif ($InputObject -is [string]) {
            $filePath = $InputObject
        } else {
            Write-Error 'InputObject must be a SubtitleFile object or a file path string.'
            return
        }

        if (-not (Test-Path $filePath)) {
            Write-Error "Subtitle file not found: $filePath"
            return
        }

        try {
            if (-not $PSCmdlet.ShouldProcess($filePath, "Upload to SubDL as '$Name' ($Language)")) {
                return
            }

            $token    = Unprotect-SubDLToken -EncryptedBase64 $script:SubDLTokenEncrypted
            $sdIdVal  = if ($SdId) { $SdId } else { '' }

            Write-Verbose "Publishing '$filePath' to SubDL (Type=$Type Language=$Language)..."

            $uploadResult = Invoke-SubDLUpload `
                -FilePath        $filePath `
                -Token           $token `
                -Name            $Name `
                -Type            $Type `
                -Language        $Language `
                -TmdbId          $TmdbId `
                -ImdbId          $ImdbId `
                -Quality         $Quality `
                -ProductionType  $ProductionType `
                -Releases        $Releases `
                -Framerate       $Framerate `
                -Comment         $Comment `
                -Season          $Season `
                -HearingImpaired $HearingImpaired.IsPresent `
                -IsFullSeason    $FullSeason.IsPresent `
                -Tags            $Tags `
                -EpisodeFrom     $EpisodeFrom `
                -EpisodeTo       $EpisodeTo `
                -SdId            $sdIdVal

            if ($uploadResult.Success) {
                Write-Verbose "SubDL: $($uploadResult.Message)"
            } else {
                Write-Warning "SubDL upload failed: $($uploadResult.Message)"
            }

            $uploadResult
        } finally {
            if ($tempFile -and (Test-Path $tempFile)) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        if ($PassThru) {
            $InputObject
        }
    }
}
