function Get-TranslationApiErrorDetail {
    <#
    .SYNOPSIS
        Extracts the provider's real error body and HTTP status code from a failed
        Invoke-RestMethod call, on both Windows PowerShell 5.1 and PowerShell 7.
    .DESCRIPTION
        Windows PowerShell 5.1 (Desktop, HttpWebRequest-based) surfaces a
        System.Net.WebException whose response body must be read from the response
        stream if Invoke-RestMethod did not already populate ErrorDetails.Message.
        PowerShell 7 (Core, HttpClient-based) surfaces a
        Microsoft.PowerShell.Commands.HttpResponseException instead. Both expose a
        duck-typed ".Response" with a ".StatusCode" property, so this reads that
        generically rather than testing for either concrete type.
    .OUTPUTS
        PSCustomObject: Message, StatusCode (StatusCode is $null when the failure
        carried no HTTP response at all - e.g. DNS failure, connection timeout).
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $statusCode = $null
    $bodyText   = $null

    # Invoke-RestMethod/-WebRequest populate ErrorDetails.Message from the response
    # body (when present) on both Desktop and Core editions - prefer it, since it is
    # the real provider JSON error rather than a generic exception message.
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $bodyText = $ErrorRecord.ErrorDetails.Message
    }

    $exception = $ErrorRecord.Exception

    if ($exception -and $exception.Response) {
        try {
            $statusCode = [int]$exception.Response.StatusCode
        } catch {
            $statusCode = $null
        }

        # Fallback body extraction for the PS 5.1 WebException shape, in case
        # ErrorDetails.Message was not populated for some reason.
        if (-not $bodyText -and ($exception.Response -is [System.Net.HttpWebResponse])) {
            try {
                $stream = $exception.Response.GetResponseStream()
                if ($stream) {
                    $reader   = [System.IO.StreamReader]::new($stream)
                    $bodyText = $reader.ReadToEnd()
                    $reader.Dispose()
                }
            } catch {
                # Response stream unavailable or already consumed - degrade gracefully
                # to the generic exception message below.
                Write-Verbose "Could not read error response stream: $_"
            }
        }
    }

    $message = if ($bodyText) { $bodyText } else { $exception.Message }

    return [PSCustomObject]@{
        Message    = $message
        StatusCode = $statusCode
    }
}

function Invoke-TranslationApiRequest {
    <#
    .SYNOPSIS
        Shared HTTP mechanics for translation provider API calls.
    .DESCRIPTION
        Centralizes what used to be copy-pasted per-adapter: exponential-backoff
        retry, UTF-8-safe JSON body encoding, and real-error-body extraction.

        Retry classification: only HTTP 429, HTTP 5xx, and network/timeout errors
        with no HTTP status at all are retried. Any other 4xx (400 bad request /
        invalid model, 401 bad key, 403 no access, 404, ...) fails fast, since
        retrying a permanent failure only wastes time.

        Content-Type is always sent via the dedicated -ContentType parameter of
        Invoke-RestMethod, never via -Headers - on Windows PowerShell 5.1 Desktop
        (HttpWebRequest-based), Content-Type is a restricted header and setting it
        through -Headers throws. A Content-Type entry in -Headers is rejected here
        so that bug cannot silently reappear in a caller.

        The JSON body is serialized and converted to UTF-8 bytes explicitly, because
        Invoke-RestMethod -Body <string> does not reliably send UTF-8 on Desktop
        edition - this module regularly ships non-ASCII subtitle text (Persian,
        Arabic, CJK, ...).
    .PARAMETER Uri
        The full request URI.
    .PARAMETER Method
        HTTP method. Defaults to Post.
    .PARAMETER Body
        Request body as a hashtable, serialized to JSON. Optional - a GET request
        (e.g. listing models) has none.
    .PARAMETER Headers
        Request headers. Must NOT contain a Content-Type entry - use the body/
        -ContentType mechanism instead.
    .PARAMETER ProviderLabel
        Human-readable provider name used in retry warning messages.
    .PARAMETER MaxRetries
        Maximum number of retries after the initial attempt (default 3, so up to
        4 attempts total with 2/4/8 second backoff).
    .PARAMETER JsonDepth
        -Depth passed to ConvertTo-Json when serializing -Body.
    .OUTPUTS
        PSCustomObject: Success, Response, ErrorMessage, StatusCode, RetryCount
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Method = 'Post',

        [hashtable] $Body,

        [hashtable] $Headers = @{},

        [string] $ProviderLabel = 'API',

        [int] $MaxRetries = 3,

        [int] $JsonDepth = 8
    )

    if ($Headers.ContainsKey('Content-Type')) {
        throw "Invoke-TranslationApiRequest: '$ProviderLabel' passed a Content-Type header. Content-Type must be sent via -ContentType (set automatically from -Body here), never via -Headers - on Windows PowerShell 5.1 Desktop it is a restricted header and setting it through -Headers throws."
    }

    $invokeParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = $Headers
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $json      = $Body | ConvertTo-Json -Depth $JsonDepth
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        $invokeParams.Body        = $bodyBytes
        $invokeParams.ContentType = 'application/json; charset=utf-8'
    }

    $attempt    = 0
    $retryCount = 0

    while ($true) {
        $attempt++
        try {
            $response = Invoke-RestMethod @invokeParams

            return [PSCustomObject]@{
                Success      = $true
                Response     = $response
                ErrorMessage = $null
                StatusCode   = 200
                RetryCount   = $retryCount
            }
        } catch {
            $detail = Get-TranslationApiErrorDetail -ErrorRecord $_

            $isRetryable = ($null -eq $detail.StatusCode) -or
                           ($detail.StatusCode -eq 429) -or
                           ($detail.StatusCode -ge 500)

            if ((-not $isRetryable) -or ($retryCount -ge $MaxRetries)) {
                return [PSCustomObject]@{
                    Success      = $false
                    Response     = $null
                    ErrorMessage = $detail.Message
                    StatusCode   = $detail.StatusCode
                    RetryCount   = $retryCount
                }
            }

            $retryCount++
            $delay = [Math]::Pow(2, $retryCount)
            Write-Warning "$ProviderLabel API call failed (attempt $attempt, status=$($detail.StatusCode)). Retrying in ${delay}s... ($retryCount/$MaxRetries retries)"
            Start-Sleep -Seconds $delay
        }
    }
}
