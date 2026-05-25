class SrtEntry : SubtitleEntry {
    [int]  $BlockNumber  # Raw number from the file (may differ from Index after renumbering)
    [bool] $HasHtmlTags  # True when text contains <b>, <i>, <u>, or <font> tags

    SrtEntry() : base() {
        $this.HasHtmlTags = $false
    }
}
