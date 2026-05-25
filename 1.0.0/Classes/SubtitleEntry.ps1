class SubtitleEntry {
    [int]       $Index       # 1-based sequence position after parsing
    [TimeSpan]  $Start       # Parsed start time (canonical internal unit)
    [TimeSpan]  $End         # Parsed end time
    [string[]]  $Lines       # Text lines — array preserves multi-line entries
    [string]    $RawText     # Original unparsed text block for lossless round-trip
    [hashtable] $Metadata    # Extension bag for format-specific extras

    SubtitleEntry() {
        $this.Metadata = @{}
        $this.Lines    = @()
    }

    [TimeSpan] Duration() {
        return $this.End - $this.Start
    }

    [string] Text() {
        return $this.Lines -join "`n"
    }

    [string] ToString() {
        return '[{0}] {1} --> {2} : {3}' -f $this.Index, $this.Start, $this.End, ($this.Lines -join ' ')
    }
}
