#Requires -Modules @{ModuleName='Pester';ModuleVersion='5.0.0'}

BeforeAll {
    $ModulePath = Join-Path (Join-Path $PSScriptRoot '..') (Join-Path '..' 'SubtitleTools.psd1')
    Import-Module $ModulePath -Force
}

Describe 'ConvertTo-MultipartFormBody' {
    # Invoke-RestMethod -Form is PowerShell 6.1+, so Publish-SubtitleFile threw a
    # parameter binding error on Windows PowerShell 5.1 - the edition the manifest
    # claims to support. The body is now built here, and these tests are the only
    # thing standing behind it: SubDL is a third-party API with no test endpoint, so
    # correctness is established against the wire format, not against their server.

    BeforeAll {
        # Latin-1 maps bytes 1:1 onto chars, so string offsets into the decoded body
        # are byte offsets - which is what makes it possible to slice the file part
        # back out and compare it byte for byte.
        $Latin1 = [System.Text.Encoding]::GetEncoding('ISO-8859-1')
    }

    It 'Emits a boundary that matches the ContentType and closes the body with it' {
        $result = InModuleScope SubtitleTools {
            ConvertTo-MultipartFormBody -Fields ([ordered]@{ a = '1' })
        }

        $result.ContentType | Should -Match '^multipart/form-data; boundary=[0-9a-f]{32}$'

        $boundary = $result.ContentType -replace '.*boundary=', ''
        $text     = [System.Text.Encoding]::UTF8.GetString($result.Body)

        $text | Should -BeLike "--$boundary`r`n*"
        $text | Should -BeLike "*`r`n--$boundary--`r`n"
    }

    It 'Writes each text field as its own part, in the order given' {
        $result = InModuleScope SubtitleTools {
            ConvertTo-MultipartFormBody -Fields ([ordered]@{
                n_id = 'session-123'
                type = 'tv'
                lang = 'Farsi/Persian'
            })
        }

        $text = [System.Text.Encoding]::UTF8.GetString($result.Body)

        $text | Should -Match 'Content-Disposition: form-data; name="n_id"\r\n\r\nsession-123\r\n'
        $text | Should -Match 'Content-Disposition: form-data; name="type"\r\n\r\ntv\r\n'
        $text | Should -Match 'Content-Disposition: form-data; name="lang"\r\n\r\nFarsi/Persian\r\n'

        # [ordered] in, same order out.
        $text.IndexOf('name="n_id"') | Should -BeLessThan $text.IndexOf('name="type"')
        $text.IndexOf('name="type"') | Should -BeLessThan $text.IndexOf('name="lang"')
    }

    It 'Carries a non-ASCII field value through as UTF-8' {
        $result = InModuleScope SubtitleTools {
            ConvertTo-MultipartFormBody -Fields ([ordered]@{ name = 'ژاپنی' })
        }

        # Decoded as UTF-8 it must read back identically, which fails if the encoder
        # is ever swapped for ASCII or the console code page - both of which turn
        # these characters into '?' rather than erroring.
        $text = [System.Text.Encoding]::UTF8.GetString($result.Body)
        $text | Should -Match ([regex]::Escape('name="name"') + '\r\n\r\n' + [regex]::Escape('ژاپنی') + '\r\n')

        # 5 Persian characters, 2 UTF-8 bytes each - not 5 bytes of '?'.
        $valueBytes = [System.Text.Encoding]::UTF8.GetBytes('ژاپنی')
        $valueBytes.Count | Should -Be 10
        $Latin1.GetString($result.Body) | Should -BeLike "*$($Latin1.GetString($valueBytes))*"
    }

    It 'Copies the attached file through byte for byte, including bytes no string survives' {
        $filePath = Join-Path $TestDrive 'subtitle.srt'

        # Deliberately hostile content: Persian text (multi-byte UTF-8), a UTF-8 BOM,
        # a lone NUL, and a bare LF that must not be normalised to CRLF.
        $original = [byte[]] (
            @(0xEF, 0xBB, 0xBF) +
            [System.Text.Encoding]::UTF8.GetBytes("1`n00:00:01,000 --> 00:00:02,000`nسلام دنیا`n") +
            @(0x00, 0xFF, 0x0A)
        )
        [System.IO.File]::WriteAllBytes($filePath, $original)

        $result = InModuleScope SubtitleTools -Parameters @{ filePath = $filePath } {
            param($filePath)
            ConvertTo-MultipartFormBody `
                -Fields ([ordered]@{ n_id = 'abc' }) `
                -FilePath $filePath -FileFieldName 'subtitle'
        }

        $boundary = $result.ContentType -replace '.*boundary=', ''
        $decoded  = $Latin1.GetString($result.Body)

        $decoded | Should -Match 'Content-Disposition: form-data; name="subtitle"; filename="subtitle\.srt"'
        $decoded | Should -Match 'Content-Type: application/octet-stream'

        $marker = "Content-Type: application/octet-stream`r`n`r`n"
        $start  = $decoded.IndexOf($marker) + $marker.Length
        $end    = $decoded.LastIndexOf("`r`n--$boundary--")
        $start  | Should -BeGreaterThan 0
        $end    | Should -BeGreaterThan $start

        $sent = $result.Body[$start..($end - 1)]
        $sent.Count | Should -Be $original.Count
        # -Be on two byte arrays compares element-wise, so a single flipped byte fails.
        $sent | Should -Be $original
    }

    It 'Keeps a non-ASCII filename in the part header instead of mangling it' {
        # A Persian .srt is exactly what this module produces, so the filename is
        # routinely non-ASCII. RFC 7578 says send it as UTF-8; that is what browsers
        # do and what SubDL will be expecting.
        $filePath = Join-Path $TestDrive 'زیرنویس.srt'
        [System.IO.File]::WriteAllBytes($filePath, [byte[]] @(0x41))

        $result = InModuleScope SubtitleTools -Parameters @{ filePath = $filePath } {
            param($filePath)
            ConvertTo-MultipartFormBody -FilePath $filePath -FileFieldName 'subtitle'
        }

        $text = [System.Text.Encoding]::UTF8.GetString($result.Body)
        $text | Should -Match ([regex]::Escape('filename="زیرنویس.srt"'))
    }

    It 'Refuses a file with no field name rather than silently dropping the part' {
        {
            InModuleScope SubtitleTools {
                ConvertTo-MultipartFormBody -FilePath 'anything.srt'
            }
        } | Should -Throw -ExpectedMessage '*FileFieldName is required*'
    }
}

Describe 'Invoke-SubDLUpload PowerShell 5.1 compatibility' {
    It 'Never passes -Form, which does not exist before PowerShell 6.1' {
        # The regression guard for the actual bug: -Form binds fine on the sandbox's
        # PowerShell 7 and throws on the 5.1 host this module claims to support, so
        # no runtime test on this box can catch its return. Read the source instead.
        $source = Get-Content (Join-Path $PSScriptRoot '../../Private/Sharing/Invoke-SubDLUpload.ps1') -Raw
        $source | Should -Not -Match '(?m)^\s*-Form\b'
        $source | Should -Match 'ConvertTo-MultipartFormBody'
    }

    It 'Sends the multipart body and its matching content type together on every upload step' {
        # Body and ContentType carry the same boundary; pairing a body with someone
        # else's content type parses server-side as an empty form, which SubDL would
        # report as a vague failure rather than an error.
        $source = Get-Content (Join-Path $PSScriptRoot '../../Private/Sharing/Invoke-SubDLUpload.ps1') -Raw

        $contentTypes = ([regex]::Matches($source, '-ContentType \$(\w+)\.ContentType')  | ForEach-Object { $_.Groups[1].Value })
        $bodies       = ([regex]::Matches($source, '-Body \$(\w+)\.Body')                | ForEach-Object { $_.Groups[1].Value })

        @($contentTypes).Count | Should -Be 2
        @($bodies).Count       | Should -Be 2
        $contentTypes          | Should -Be $bodies
    }
}
