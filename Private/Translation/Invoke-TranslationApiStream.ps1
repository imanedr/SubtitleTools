function Get-TranslationStreamReasoning {
    <#
    .SYNOPSIS
        Extracts the reasoning ("thinking") text carried by one OpenAI-shape streaming
        delta, across the several different field names providers spell it with.
    .DESCRIPTION
        There is no standard for this field. DeepSeek's own API sends a flat
        `reasoning_content` string. OpenRouter normalises to `reasoning` and also emits
        a structured `reasoning_details` array whose entries carry `text`, `summary`,
        or - for upstreams that only hand back an opaque blob - `data`. Reading just
        one of these means the thinking phase goes undetected on the providers that use
        the others, which is how this went unnoticed: OpenRouter is the usual route to
        a reasoning model here, and it does not send `reasoning_content`.
    .PARAMETER Delta
        The `choices[0].delta` object from one SSE frame.
    .OUTPUTS
        [string] the reasoning text in this frame, or $null when the frame carried no
        reasoning field at all. The difference matters: a frame whose only reasoning is
        an encrypted blob yields '' rather than $null, which still tells the caller the
        model is thinking even though there is no text to show for it.
    #>
    [OutputType([string])]
    param($Delta)

    if ($null -eq $Delta) { return $null }

    if ($null -ne $Delta.reasoning_content) { return [string]$Delta.reasoning_content }
    if ($null -ne $Delta.reasoning)         { return [string]$Delta.reasoning }

    if ($null -ne $Delta.reasoning_details) {
        $text = ''
        foreach ($detail in @($Delta.reasoning_details)) {
            if ($null -eq $detail) { continue }
            if     ($null -ne $detail.text)    { $text += [string]$detail.text }
            elseif ($null -ne $detail.summary) { $text += [string]$detail.summary }
        }
        return $text
    }

    return $null
}

function Read-TranslationSseStream {
    <#
    .SYNOPSIS
        Decodes a server-sent-events response body into translated text, token counts,
        and live progress callbacks.
    .DESCRIPTION
        Split out from Invoke-TranslationApiStream so the protocol half is separable
        from the transport half. It takes any TextReader, so the entire decode - the
        three provider event shapes, the reasoning phase, usage and finish reasons -
        can be exercised against a canned response body with no HTTP involved. The
        loop is the part with the interesting edge cases; leaving it welded to
        HttpClient meant none of them could be tested.

        SSE framing is deliberately minimal: only "data:" lines are read, "[DONE]" ends
        the stream, and a payload that will not parse as JSON is skipped rather than
        throwing - a partially flushed frame is normal mid-stream and must not kill an
        otherwise good response.
    .PARAMETER Reader
        Reader positioned at the start of the response body.
    .PARAMETER Shape
        Which provider's event schema to decode: OpenAI (also OpenRouter), Anthropic,
        or Google.
    .PARAMETER OnDelta
        See Invoke-TranslationApiStream -OnDelta.
    .OUTPUTS
        Hashtable: Content, InputTokens, OutputTokens, FinishReason, ErrorMessage
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.IO.TextReader] $Reader,

        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $Shape,

        [scriptblock] $OnDelta
    )

    $result = @{
        Content      = ''
        InputTokens  = 0
        OutputTokens = 0
        FinishReason = $null
        ErrorMessage = $null
    }

    $builder        = [System.Text.StringBuilder]::new()
    $reasoningSoFar = [System.Text.StringBuilder]::new()

    while ($null -ne ($line = $Reader.ReadLine())) {

        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith('data:'))       { continue }

        $payload = $line.Substring(5).Trim()
        if ($payload -eq '[DONE]') { break }

        try {
            $sse = $payload | ConvertFrom-Json
        } catch {
            # A partially flushed frame is normal mid-stream - skip it.
            continue
        }

        $delta = $null
        # $null means "this frame carried no reasoning field"; '' means it carried one
        # with no readable text, which still says the model is thinking.
        $reasonText = $null

        switch ($Shape) {
            'OpenAI' {
                $choice = $sse.choices | Select-Object -First 1
                if ($choice) {
                    $delta = $choice.delta.content
                    if ($choice.finish_reason) { $result.FinishReason = $choice.finish_reason }

                    # Reasoning models spend minutes emitting thinking tokens before a
                    # single visible character appears. Accumulate them so the caller
                    # can show that phase instead of a frozen bar.
                    $reasonText = Get-TranslationStreamReasoning -Delta $choice.delta
                    if ($reasonText) { $null = $reasoningSoFar.Append($reasonText) }
                }
                # Present only on the final chunk, and only when the request asked
                # for stream_options.include_usage.
                if ($sse.usage) {
                    if ($null -ne $sse.usage.prompt_tokens)     { $result.InputTokens  = [int]$sse.usage.prompt_tokens }
                    if ($null -ne $sse.usage.completion_tokens) { $result.OutputTokens = [int]$sse.usage.completion_tokens }
                }
            }
            'Anthropic' {
                switch ($sse.type) {
                    'message_start' {
                        if ($sse.message.usage.input_tokens) { $result.InputTokens = [int]$sse.message.usage.input_tokens }
                    }
                    'content_block_delta' {
                        # Only text_delta carries the answer. thinking_delta is the
                        # model's scratchpad: it is surfaced as the reasoning phase
                        # below, never appended to the translation itself.
                        if ($sse.delta.type -eq 'text_delta') {
                            $delta = $sse.delta.text
                        } elseif ($sse.delta.type -eq 'thinking_delta') {
                            $reasonText = [string]$sse.delta.thinking
                            if ($reasonText) { $null = $reasoningSoFar.Append($reasonText) }
                        }
                    }
                    'message_delta' {
                        if ($sse.delta.stop_reason)    { $result.FinishReason = $sse.delta.stop_reason }
                        if ($sse.usage.output_tokens)  { $result.OutputTokens = [int]$sse.usage.output_tokens }
                    }
                    'error' {
                        $result.ErrorMessage = "$($sse.error.type): $($sse.error.message)"
                    }
                }
            }
            'Google' {
                $candidate = $sse.candidates | Select-Object -First 1
                if ($candidate) {
                    $delta = ($candidate.content.parts | ForEach-Object { $_.text }) -join ''
                    if ($candidate.finishReason) { $result.FinishReason = $candidate.finishReason }
                }
                if ($sse.usageMetadata) {
                    if ($null -ne $sse.usageMetadata.promptTokenCount)     { $result.InputTokens  = [int]$sse.usageMetadata.promptTokenCount }
                    if ($null -ne $sse.usageMetadata.candidatesTokenCount) { $result.OutputTokens = [int]$sse.usageMetadata.candidatesTokenCount }
                }
            }
        }

        if ($delta) {
            $null = $builder.Append($delta)

            if ($OnDelta) {
                & $OnDelta $builder.ToString() @{
                    InputTokens     = $result.InputTokens
                    OutputTokens    = $result.OutputTokens
                    ReasoningLength = $reasoningSoFar.Length
                    Reasoning       = $false
                }
            }
        } elseif ($OnDelta -and $null -ne $reasonText -and $builder.Length -eq 0) {
            # Still thinking: this frame carried reasoning AND not one visible
            # character has arrived yet. Both halves matter. Firing on "reasoning was
            # seen at some point" instead would re-raise the thinking phase on every
            # later contentless frame - the finish_reason chunk, the usage-only chunk,
            # a keepalive - which sends the caller's progress bar backwards partway
            # through a response that is in fact still advancing.
            & $OnDelta $builder.ToString() @{
                InputTokens     = $result.InputTokens
                OutputTokens    = $result.OutputTokens
                ReasoningLength = $reasoningSoFar.Length
                Reasoning       = $true
            }
        }
    }

    $result.Content = $builder.ToString()
    return $result
}

function Invoke-TranslationApiStream {
    <#
    .SYNOPSIS
        Makes a streaming (server-sent events) translation API call, reporting text
        back to the caller as it arrives rather than only at the end.
    .DESCRIPTION
        Invoke-RestMethod buffers the whole response before returning, so a batch that
        takes 40 seconds to generate produces no signal for 40 seconds. This reads the
        response body incrementally instead, so the caller can show real progress
        while the model is still writing.

        Implemented on System.Net.Http.HttpClient with ResponseHeadersRead rather than
        Invoke-WebRequest, because that is the one HTTP client available on BOTH
        Windows PowerShell 5.1 Desktop (.NET Framework 4.5+) and PowerShell 7 that can
        hand back the response stream before the body is complete. Invoke-RestMethod
        cannot do this on Desktop edition at all.

        This function owns the transport only; Read-TranslationSseStream decodes the
        body it opens.

        Callers are expected to treat a failure here as recoverable and fall back to
        the buffered path (see Invoke-TranslationApiRequest); nothing in the module
        depends on streaming succeeding.
    .PARAMETER Uri
        Full request URI. For Google this is the :streamGenerateContent?alt=sse form.
    .PARAMETER Headers
        Request headers. Content-Type is set from the request body and must not appear
        here (same restricted-header constraint as the buffered path).
    .PARAMETER Body
        Request body hashtable, serialized to JSON.
    .PARAMETER Shape
        Which provider's event schema to decode: OpenAI (also OpenRouter), Anthropic,
        or Google.
    .PARAMETER OnDelta
        Optional scriptblock invoked as the response arrives, with two arguments: the
        full text accumulated so far, and a hashtable of counters so far
        (@{ InputTokens; OutputTokens; ReasoningLength; Reasoning }). Throttling is the
        caller's responsibility.

        A reasoning model produces nothing visible for minutes while it thinks, so the
        callback also fires during that phase, with Reasoning = $true and an empty
        accumulated string - otherwise a long think is indistinguishable from a hang.
        Reasoning is $true only BEFORE the first visible character arrives; from then
        on it stays $false for the rest of the response, so a caller driving a progress
        bar off it never sees the phase flip backwards.
    .PARAMETER JsonDepth
        -Depth for ConvertTo-Json on the request body.
    .PARAMETER TimeoutSec
        Overall request timeout.
    .OUTPUTS
        Hashtable: Success, Content, InputTokens, OutputTokens, FinishReason,
        StatusCode, ErrorMessage
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [hashtable] $Headers = @{},

        [Parameter(Mandatory)]
        [hashtable] $Body,

        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $Shape,

        [scriptblock] $OnDelta,

        [int] $JsonDepth = 8,

        [int] $TimeoutSec = 600
    )

    if ($Headers.ContainsKey('Content-Type')) {
        throw "Invoke-TranslationApiStream: Content-Type must not be passed via -Headers; it is set from the request body."
    }

    # System.Net.Http is a framework assembly on Desktop edition and must be loaded
    # explicitly; on Core it is already present and this is a no-op.
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    # Desktop edition can default to a protocol the providers no longer accept.
    try {
        if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
    } catch {
        Write-Verbose "Could not raise SecurityProtocol to TLS 1.2: $_"
    }

    $result = @{
        Success      = $false
        Content      = ''
        InputTokens  = 0
        OutputTokens = 0
        FinishReason = $null
        StatusCode   = $null
        ErrorMessage = $null
    }

    $json   = $Body | ConvertTo-Json -Depth $JsonDepth
    $client = $null
    $reader = $null

    try {
        $client         = [System.Net.Http.HttpClient]::new()
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
        foreach ($name in $Headers.Keys) {
            $null = $request.Headers.TryAddWithoutValidation([string]$name, [string]$Headers[$name])
        }
        $request.Content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')

        $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $result.StatusCode = [int]$response.StatusCode

        if (-not $response.IsSuccessStatusCode) {
            $result.ErrorMessage = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            return $result
        }

        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

        $decoded = Read-TranslationSseStream -Reader $reader -Shape $Shape -OnDelta $OnDelta

        $result.InputTokens  = $decoded.InputTokens
        $result.OutputTokens = $decoded.OutputTokens
        $result.FinishReason = $decoded.FinishReason
        $result.ErrorMessage = $decoded.ErrorMessage

        if ($result.ErrorMessage) { return $result }

        $result.Content = $decoded.Content
        $result.Success = $true
        return $result

    } catch {
        # Network failure, TLS failure, a runtime that cannot load System.Net.Http -
        # all reported the same way, because the caller's response to any of them is
        # the same: fall back to the buffered request path.
        $result.ErrorMessage = $_.Exception.Message
        return $result
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

function Invoke-TranslationStreamAttempt {
    <#
    .SYNOPSIS
        Runs one provider call over the streaming path, or reports that the caller
        should fall back to the buffered path.
    .DESCRIPTION
        Shared by all four adapters so the "try streaming, degrade gracefully" policy
        lives in exactly one place.

        Streaming is a progress-reporting nicety, never a correctness requirement, so
        it must never be the reason a translation fails. The decision table:

          stream succeeded            -> return the adapter-shaped result
          HTTP 4xx other than 429     -> return an error result; the buffered path
                                         would fail identically, so re-sending it
                                         would just cost a second request
          HTTP 429 / 5xx              -> return $null, so the caller falls back and
                                         gets the buffered path's backoff-retry loop
          no HTTP status at all       -> return $null and fall back (transport error,
                                         TLS failure, no System.Net.Http, a provider
                                         or gateway that does not do SSE)
    .OUTPUTS
        PSCustomObject in the adapter contract shape, or $null meaning "fall back".
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [hashtable] $Headers = @{},

        [Parameter(Mandatory)]
        [hashtable] $Body,

        [Parameter(Mandatory)]
        [ValidateSet('OpenAI', 'Anthropic', 'Google')]
        [string] $Shape,

        [Parameter(Mandatory)]
        [string] $ProviderLabel,

        [Parameter(Mandatory)]
        [string] $Model,

        [scriptblock] $StreamCallback,

        [int] $JsonDepth = 8
    )

    $streamBody = $Body.Clone()
    $streamBody['stream'] = $true
    if ($Shape -eq 'OpenAI') {
        # Without this the final chunk carries no usage block and token counts come
        # back as zero.
        $streamBody['stream_options'] = @{ include_usage = $true }
    }

    $stream = Invoke-TranslationApiStream -Uri $Uri -Headers $Headers -Body $streamBody `
        -Shape $Shape -OnDelta $StreamCallback -JsonDepth $JsonDepth

    if ($stream.Success) {
        return [PSCustomObject]@{
            Content      = $stream.Content
            InputTokens  = $stream.InputTokens
            OutputTokens = $stream.OutputTokens
            FinishReason = $stream.FinishReason
            Model        = $Model
            RetryCount   = 0
        }
    }

    $status = $stream.StatusCode

    if ($null -ne $status -and $status -ge 400 -and $status -lt 500 -and $status -ne 429) {
        Write-Verbose "$ProviderLabel streaming request failed with HTTP $status; not retrying on the buffered path."
        return [PSCustomObject]@{
            Content      = $stream.ErrorMessage
            InputTokens  = 0
            OutputTokens = 0
            FinishReason = 'error'
            Model        = $Model
            RetryCount   = 0
        }
    }

    Write-Verbose "$ProviderLabel streaming unavailable (status=$status): $($stream.ErrorMessage). Falling back to a buffered request."
    return $null
}
