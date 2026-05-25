function Split-SubtitleFile {
    <#
    .SYNOPSIS
        Splits a SubtitleFile into multiple files by time range or entry count.
    .DESCRIPTION
        Use -AtTime to split at a specific timestamp (entries before go to first output,
        entries at or after go to second output).
        Use -ChunkSize to split into equal-sized chunks.
    .PARAMETER InputObject
        A SubtitleFile object.
    .PARAMETER AtTime
        A TimeSpan at which to split the file into two parts.
    .PARAMETER ChunkSize
        Number of entries per chunk (splits into N/ChunkSize files).
    .EXAMPLE
        $parts = Import-SubtitleFile 'long.srt' | Split-SubtitleFile -AtTime '01:00:00'
        $parts[0] | Export-SubtitleFile -Path 'part1.srt'
        $parts[1] | Export-SubtitleFile -Path 'part2.srt'
    .EXAMPLE
        Import-SubtitleFile 'movie.srt' | Split-SubtitleFile -ChunkSize 100
    #>
    [CmdletBinding(DefaultParameterSetName = 'AtTime')]
    [OutputType('SubtitleFile[]')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [SubtitleFile] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'AtTime')]
        [TimeSpan] $AtTime,

        [Parameter(Mandatory, ParameterSetName = 'ChunkSize')]
        [int] $ChunkSize
    )

    process {
        $results = [System.Collections.Generic.List[SubtitleFile]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'AtTime') {
            $before = @($InputObject.Entries | Where-Object { $_.Start -lt $AtTime })
            $after  = @($InputObject.Entries | Where-Object { $_.Start -ge $AtTime })

            foreach ($group in @($before, $after)) {
                $chunk           = [SubtitleFile]::new()
                $chunk.Format    = $InputObject.Format
                $chunk.Encoding  = $InputObject.Encoding
                $chunk.Header    = $InputObject.Header
                $chunk.Entries   = $group

                # Re-index
                $i = 1
                foreach ($e in $chunk.Entries) { $e.Index = $i++ }

                $results.Add($chunk)
            }
        } else {
            $allEntries = $InputObject.Entries
            $total      = $allEntries.Count

            for ($start = 0; $start -lt $total; $start += $ChunkSize) {
                $sliceEnd   = [Math]::Min($start + $ChunkSize, $total) - 1
                $slice      = $allEntries[$start..$sliceEnd]

                $chunk          = [SubtitleFile]::new()
                $chunk.Format   = $InputObject.Format
                $chunk.Encoding = $InputObject.Encoding
                $chunk.Header   = $InputObject.Header
                $chunk.Entries  = $slice

                $i = 1
                foreach ($e in $chunk.Entries) { $e.Index = $i++ }

                $results.Add($chunk)
            }
        }

        return $results.ToArray()
    }
}
