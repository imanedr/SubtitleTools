class AssStyle {
    [string]  $Name
    [string]  $Fontname
    [int]     $Fontsize
    [string]  $PrimaryColour    # ASS ABGR hex format: &H00FFFFFF&
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
    [int]     $Alignment       # Numpad layout: 1-9
    [int]     $MarginL
    [int]     $MarginR
    [int]     $MarginV
    [int]     $Encoding

    AssStyle() {
        # Sensible defaults matching a typical Default style
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

    # Serialize to ASS Style: line value
    [string] ToAssLine() {
        $b = if ($this.Bold)      { '-1' } else { '0' }
        $i = if ($this.Italic)    { '-1' } else { '0' }
        $u = if ($this.Underline) { '-1' } else { '0' }
        $s = if ($this.StrikeOut) { '-1' } else { '0' }
        return 'Style: {0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},{17},{18},{19},{20}' -f `
            $this.Name, $this.Fontname, $this.Fontsize,
            $this.PrimaryColour, $this.SecondaryColour, $this.OutlineColour, $this.BackColour,
            $b, $i, $u, $s,
            $this.ScaleX, $this.ScaleY, $this.Spacing, $this.Angle,
            $this.BorderStyle, $this.Outline, $this.Shadow,
            $this.Alignment, $this.MarginL, $this.MarginR, $this.MarginV, $this.Encoding
    }
}
