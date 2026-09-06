function Invoke-SubDLUpload {
    <#
    .SYNOPSIS
        Uploads a subtitle file to SubDL via their three-step Upload API.
    .DESCRIPTION
        Executes the three API steps in sequence:
          1. GET /user/getNId              — obtain a session identifier (n_id)
          2. POST /user/uploadSingleSubtitle — upload the subtitle file, receive file_n_id
          3. POST /user/uploadSubtitle     — submit metadata and complete the upload

        Returns a PSCustomObject with Success and Message fields.
        Use -Verbose to log raw API responses for debugging.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string] $Token,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Type,            # 'movie' | 'tv'

        [Parameter(Mandatory)]
        [string] $Language,        # ISO 639-1 code (e.g. 'fa') or full SubDL name

        [string] $TmdbId,
        [string] $ImdbId,

        [string]   $Quality        = 'web',
        [int]      $ProductionType = 0,
        [string[]] $Releases       = @(),
        [int]      $Framerate      = 0,
        [string]   $Comment        = '',
        [int]      $Season         = 0,
        [bool]     $HearingImpaired = $false,
        [bool]     $IsFullSeason   = $false,
        [string[]] $Tags           = @(),
        [int]      $EpisodeFrom    = 0,
        [int]      $EpisodeTo      = 0,
        [string]   $SdId           = ''
    )

    $result = [PSCustomObject]@{
        Success = $false
        Message = ''
    }

    try {
        $baseUrl = 'https://api3.subdl.com'
        $bearerHeader = @{ authorization = "Bearer $Token" }

        # Resolve language code to SubDL display name
        $langKey     = $Language.ToLower()
        $langResolved = $Language   # default: pass through as-is
        if ($script:SubDLLanguages -and
            ($script:SubDLLanguages | Get-Member -Name $langKey -MemberType NoteProperty -ErrorAction SilentlyContinue)) {
            $langResolved = $script:SubDLLanguages.$langKey
        }
        Write-Verbose "Language resolved: '$Language' -> '$langResolved'"

        # ------------------------------------------------------------------
        # Step 1: Get session identifier (n_id)
        # ------------------------------------------------------------------
        Write-Verbose 'SubDL Step 1: Getting session n_id...'

        $step1 = Invoke-RestMethod -Uri "$baseUrl/user/getNId" `
            -Method GET -Headers $bearerHeader -ErrorAction Stop

        Write-Verbose "SubDL Step 1 response: ok=$($step1.ok) n_id=$($step1.n_id)"

        if (-not $step1.ok) {
            $result.Message = "Step 1 failed: $($step1.error)"
            return $result
        }

        $nId = $step1.n_id

        # ------------------------------------------------------------------
        # Step 2: Upload the subtitle file
        # ------------------------------------------------------------------
        Write-Verbose "SubDL Step 2: Uploading file '$FilePath'..."

        $step2 = Invoke-RestMethod -Uri "$baseUrl/user/uploadSingleSubtitle" `
            -Method POST `
            -Headers $bearerHeader `
            -Form @{
                subtitle = Get-Item -LiteralPath $FilePath
                n_id     = $nId
            } `
            -ErrorAction Stop

        Write-Verbose "SubDL Step 2 response: ok=$($step2.ok) file_n_id=$($step2.file.file_n_id)"

        if (-not $step2.ok) {
            $result.Message = "Step 2 failed: $($step2.error)"
            return $result
        }

        $fileNId = $step2.file.file_n_id

        # ------------------------------------------------------------------
        # Step 3: Submit metadata and complete the upload
        # ------------------------------------------------------------------
        Write-Verbose 'SubDL Step 3: Submitting metadata...'

        $form3 = [ordered]@{
            file_n_ids      = ConvertTo-Json @($fileNId) -Compress
            n_id            = $nId
            type            = $Type
            name            = $Name
            lang            = $langResolved
            quality         = $Quality
            production_type = $ProductionType.ToString()
            framerate       = $Framerate.ToString()
            comment         = $Comment
            season          = $Season.ToString()
            hi              = $HearingImpaired.ToString().ToLower()
            is_full_season  = $IsFullSeason.ToString().ToLower()
            releases        = ConvertTo-Json $Releases -Compress
            tags            = ConvertTo-Json $Tags -Compress
        }

        if ($TmdbId) { $form3['tmdb_id'] = $TmdbId }
        if ($ImdbId) { $form3['imdb_id'] = $ImdbId  }
        if ($EpisodeFrom -gt 0) { $form3['ef'] = $EpisodeFrom.ToString() }
        if ($EpisodeTo   -gt 0) { $form3['ee'] = $EpisodeTo.ToString()   }
        if ($SdId)              { $form3['sd_id'] = $SdId                }

        $step3 = Invoke-RestMethod -Uri "$baseUrl/user/uploadSubtitle" `
            -Method POST `
            -Headers $bearerHeader `
            -Form $form3 `
            -ErrorAction Stop

        Write-Verbose "SubDL Step 3 response: status=$($step3.status) message=$($step3.message)"

        if ($step3.status) {
            $result.Success = $true
            $result.Message = $step3.message
        } else {
            $result.Message = $step3.message
        }

    } catch {
        $result.Message = "Error: $_"
        Write-Verbose "SubDL upload error: $_"
    }

    return $result
}
