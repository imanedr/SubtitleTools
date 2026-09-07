# SubtitleTools

**A comprehensive PowerShell module for SRT and ASS/SSA subtitle files.**  
Parse, validate, repair, sync, convert, and AI-translate subtitles — all from the command line or your own scripts.

[![PSGallery Version](https://img.shields.io/powershellgallery/v/SubtitleTools?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/SubtitleTools)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)

---

## Table of Contents

- [Features](#features)
- [AI Translation — The Headline Feature](#ai-translation--the-headline-feature)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Validation & Repair](#validation--repair)
- [Timestamp Manipulation](#timestamp-manipulation)
- [ASS / SSA Advanced Features](#ass--ssa-advanced-features)
- [AI Translation](#ai-translation)
  - [Setup](#setup)
  - [Basic Translation](#basic-translation)
  - [Content-Aware Translation (Priming)](#content-aware-translation-priming)
  - [Using a Glossary](#using-a-glossary)
  - [Sessions, Caching & Resume](#sessions-caching--resume)
  - [Progress & Live Output](#progress--live-output)
  - [Run Summary](#run-summary)
  - [Batch Size & Truncated Responses](#batch-size--truncated-responses)
  - [Back-Translation Verification](#back-translation-verification)
  - [Post-Translation Line Wrapping](#post-translation-line-wrapping)
- [Batch Processing](#batch-processing)
- [Sharing / Publishing](#sharing--publishing)
- [Utilities](#utilities)
- [All Functions](#all-functions)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [License](#license)
- [Changelog](#changelog)

---

## Features

- **Parse & serialize** SRT and ASS/SSA files with full round-trip fidelity
- **Validate** — detect malformed blocks, timestamp issues, and overlapping entries
- **Repair** — fix numbering, encoding (UTF-16, Windows-1252 → UTF-8), timestamp separators, overlaps
- **Timestamp manipulation** — shift, stretch (two-point drift correction), merge, split, sync to reference
- **ASS/SSA advanced** — style CRUD, override tag stripping, plain-text extraction, SRT↔ASS conversion
- **AI translation** — OpenAI, Anthropic, Google, and OpenRouter with batching, caching, glossary, and resume
- **Translation quality** — back-translation verification, line-width wrapping
- **Batch processing** — apply any operation to all subtitle files in a directory tree

---

## AI Translation — The Headline Feature

> SubtitleTools wraps four major AI APIs — including OpenRouter's gateway to hundreds of hosted models — into a single, pipeline-friendly PowerShell interface designed for subtitle work specifically.

**What sets it apart:**

| Capability | Description |
|------------|-------------|
| **Multi-provider** | Switch between OpenAI, Anthropic, Google, and OpenRouter with one parameter |
| **Content-aware priming** | Analyzes the content first (genre, tone, terminology) and embeds that context into every translation batch — critical for consistent, idiomatic results |
| **Glossary injection** | Enforce fixed translations for character names, titles, and jargon across an entire series |
| **Back-translation verification** | Re-translate back to the source language and flag entries where meaning was lost |
| **Batch entire series** | Translate a full season in one command with per-session caching |
| **Resume from checkpoint** | If interrupted, pick up exactly where you left off |
| **ASS tag preservation** | Override tags (`{\i1}`, `{\pos(...)}`, etc.) are stripped before sending to the AI and reinserted after — the AI never sees formatting noise |

```powershell
# Translate a movie to Persian with content-aware priming
Invoke-SubtitleTranslation `
    -Path 'movie.srt' `
    -ProviderName Anthropic `
    -TargetLanguage 'fa' `
    -PrimeWithContext `
    -OutputPath 'movie.fa.srt'

# Translate an entire anime series with a glossary and session caching
$session = New-TranslationSession -ProviderName OpenAI -GlossaryPath './glossary.json'
Get-ChildItem 'D:\Shows\Season1' -Filter '*.srt' | ForEach-Object {
    Import-SubtitleFile $_.FullName |
        Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session |
        Export-SubtitleFile -Path ($_.FullName -replace '\.srt$', '.fa.srt')
}
```

---

## Installation

### Option A — PowerShell Gallery (recommended)

```powershell
Install-Module -Name SubtitleTools -Scope CurrentUser
```

### Option B — Manual install

```powershell
# Copy the module files into a version-named folder on your module path
Copy-Item -Path '.\SubtitleTools\*' `
    -Destination "$([Environment]::GetFolderPath('MyDocuments'))\PowerShell\Modules\SubtitleTools\1.3.1" `
    -Recurse
```

### Option C — Import directly from the cloned repo

```powershell
Import-Module 'C:\path\to\SubtitleTools\SubtitleTools.psd1' -Force
```

### Verify

```powershell
Get-Command -Module SubtitleTools | Sort-Object Name
Get-Help about_SubtitleTools
```

---

## Quick Start

```powershell
# Inspect a subtitle file
Get-SubtitleInfo -Path 'movie.srt'

# Validate
Test-SrtFile -Path 'movie.srt'

# Shift all subtitles forward by 2.5 seconds
Import-SubtitleFile 'movie.srt' |
    Add-SubtitleOffset -Seconds 2.5 |
    Export-SubtitleFile -Path 'movie_fixed.srt'

# Repair common issues and re-save
Repair-SrtFile -Path 'broken.srt' -OutputPath 'fixed.srt'

# Fix encoding (UTF-16 / Windows-1252 → UTF-8)
Repair-SubtitleEncoding -Path 'legacy.srt'

# Convert ASS to SRT
Import-SubtitleFile 'anime.ass' |
    Convert-AssToSrt |
    Export-SubtitleFile -Path 'anime.srt'
```

---

## Core Concepts

### The SubtitleFile Object

Most functions accept and return a `SubtitleFile` object — the central data structure:

```powershell
$sub = Import-SubtitleFile 'anime.ass'

$sub.Format          # 'ASS'
$sub.Encoding        # 'UTF-8'
$sub.Entries.Count   # number of dialogue lines
$sub.Header.Styles   # ASS styles array
$sub.Entries[0].Start  # [TimeSpan] start time
$sub.Entries[0].Lines  # [string[]] text lines
```

Functions are designed to chain in a pipeline:

```powershell
Import-SubtitleFile 'raw.srt' |
    Repair-SubtitleOverlap -Strategy Trim |
    Add-SubtitleOffset -Seconds -0.5 |
    Optimize-SubtitleFile |
    Export-SubtitleFile -Path 'clean.srt'
```

### Timestamps

All timestamps are stored as `[TimeSpan]` internally. Format-specific string conversion (`HH:mm:ss,fff` for SRT; `H:mm:ss.cc` for ASS) happens automatically at read and write time.

---

## Validation & Repair

```powershell
# Full SRT validation — returns a ValidationResult object
$result = Test-SrtFile -Path 'movie.srt'
$result.IsValid
$result.Errors    | Format-Table
$result.Warnings  | Format-Table

# Check for overlapping entries
Import-SubtitleFile 'movie.srt' | Test-SubtitleOverlap

# Fix overlaps (Trim, Shift, or Drop strategy)
Import-SubtitleFile 'movie.srt' |
    Repair-SubtitleOverlap -Strategy Trim -Gap 50 |
    Export-SubtitleFile -Path 'fixed.srt'

# Fix encoding
Repair-SubtitleEncoding -Path 'old.srt' -OutputPath 'utf8.srt'

# Repair an ASS file (adds missing sections, fixes unclosed tags)
Repair-AssFile -Path 'broken.ass' -OutputPath 'fixed.ass'
```

---

## Timestamp Manipulation

```powershell
# Shift all entries 1.5 seconds earlier
Import-SubtitleFile 'late.srt' |
    Add-SubtitleOffset -Seconds -1.5 |
    Export-SubtitleFile -Path 'synced.srt'

# Shift only entries 50 through 100
Import-SubtitleFile 'movie.srt' |
    Add-SubtitleOffset -Milliseconds 800 -EntryRange (50..100) |
    Export-SubtitleFile -Path 'partial.srt'

# Fix drift with two sync points
Import-SubtitleFile 'drifting.srt' |
    Invoke-SubtitleStretch `
        -SourcePoint1 '01:00:00' -TargetPoint1 '01:00:02' `
        -SourcePoint2 '01:30:00' -TargetPoint2 '01:30:09' |
    Export-SubtitleFile -Path 'stretched.srt'

# Merge two subtitle tracks into one
Merge-SubtitleFile -Primary (Import-SubtitleFile 'full.srt') `
                   -Secondary (Import-SubtitleFile 'forced.srt') |
    Export-SubtitleFile -Path 'merged.srt'

# Split at the 1-hour mark
$parts = Import-SubtitleFile 'long.srt' | Split-SubtitleFile -AtTime '01:00:00'
$parts[0] | Export-SubtitleFile -Path 'part1.srt'
$parts[1] | Export-SubtitleFile -Path 'part2.srt'

# Get duration statistics
Import-SubtitleFile 'movie.srt' | Get-SubtitleDuration
```

---

## ASS / SSA Advanced Features

```powershell
# List styles
Import-SubtitleFile 'anime.ass' | Get-AssStyle

# Change font and size of the Default style
Import-SubtitleFile 'anime.ass' |
    Set-AssStyle -Name 'Default' -Fontname 'Calibri' -Fontsize 24 |
    Export-SubtitleFile -Path 'restyled.ass'

# Add a new style
Import-SubtitleFile 'anime.ass' |
    New-AssStyle -Name 'Signs' -Fontsize 18 -Alignment 8 -Italic $true |
    Export-SubtitleFile -Path 'with_signs_style.ass'

# Strip all override tags ({\pos(...)}, {\fad(...)}, etc.)
Import-SubtitleFile 'anime.ass' |
    Remove-AssOverrideTag |
    Export-SubtitleFile -Path 'no_tags.ass'

# Extract plain text only
Import-SubtitleFile 'anime.ass' | Convert-AssToPlainText

# Convert ASS → SRT
Import-SubtitleFile 'anime.ass' |
    Convert-AssToSrt |
    Export-SubtitleFile -Path 'anime.srt'

# Convert SRT → ASS (with a custom template for styles)
$template = Import-SubtitleFile 'my_template.ass'
Import-SubtitleFile 'movie.srt' |
    Convert-SrtToAss -TemplateFile $template |
    Export-SubtitleFile -Path 'movie.ass'
```

---

## AI Translation

Supports **OpenAI**, **Anthropic**, **Google**, and **OpenRouter** AI APIs.

### Setup

Provider configs and API keys are saved to `%APPDATA%\SubtitleTools\providers.json`. Keys are encrypted with **Windows DPAPI** (tied to your Windows user account) — no vault, no password prompt.

```powershell
# First-time setup — save provider config and encrypt API key
Set-TranslationProvider -Name Anthropic -Model 'claude-sonnet-5' -ApiKeyPlainText 'sk-ant-...'
Set-TranslationProvider -Name OpenAI    -Model 'gpt-4o'                    -ApiKeyPlainText 'sk-...'
Set-TranslationProvider -Name Google    -Model 'gemini-2.0-flash'           -ApiKeyPlainText 'AIza...'

# Switch active provider (no key needed for previously saved providers)
Set-TranslationProvider -Name Google

# Update only the model (API key is preserved)
Set-TranslationProvider -Name Google -Model 'gemini-1.5-pro'

# List configured providers
Get-TranslationProvider

# Remove a saved provider
Remove-TranslationProvider -Name OpenAI
```

### OpenRouter

[OpenRouter](https://openrouter.ai) is a unified gateway to hundreds of hosted models (Anthropic, OpenAI, Google, Meta, and more) behind one OpenAI-compatible API and one API key. `Get-OpenRouterModel` discovers current model IDs — no API key required — before you configure the provider:

```powershell
# Discover current Anthropic models available via OpenRouter (no API key needed)
Get-OpenRouterModel -Filter 'anthropic/*' |
    Format-Table Id, ContextLength, PromptPricePerMTok, CompletionPricePerMTok

# Configure and activate OpenRouter with a chosen model
Set-TranslationProvider -Name OpenRouter -Model 'anthropic/claude-sonnet-5' -ApiKeyPlainText 'sk-or-...'
```

### Basic Translation

```powershell
# Translate to Persian
Invoke-SubtitleTranslation `
    -Path 'movie.srt' `
    -ProviderName Anthropic `
    -TargetLanguage 'fa' `
    -OutputPath 'movie.fa.srt'

# Translate via pipeline
Import-SubtitleFile 'anime.ass' |
    Invoke-SubtitleTranslation -ProviderName OpenAI -TargetLanguage 'fr' |
    Export-SubtitleFile -Path 'anime.fr.ass'
```

### Content-Aware Translation (Priming)

Run a **priming pass** before translation — the module analyzes a sample of the content (genre, tone, register, domain terminology, cultural notes) and embeds that context into every subsequent batch prompt. This produces noticeably more consistent and idiomatic translations.

For multi-episode series, priming runs once on the first episode; all subsequent episodes reuse the same context at no extra API cost.

```powershell
# Single file — auto-analyze content before translating
Invoke-SubtitleTranslation `
    -Path 'movie.srt' `
    -ProviderName Anthropic `
    -TargetLanguage 'fa' `
    -PrimeWithContext `
    -OutputPath 'movie.fa.srt'

# Anime series — prime on episode 1, reuse for all others
$session = New-TranslationSession -ProviderName Anthropic -GlossaryPath './glossary.json'

Import-SubtitleFile 'ep01.srt' |
    Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session -PrimeWithContext |
    Export-SubtitleFile -Path 'ep01.fa.srt'

2..12 | ForEach-Object {
    Import-SubtitleFile "ep$('{0:D2}' -f $_).srt" |
        Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session |
        Export-SubtitleFile -Path "ep$('{0:D2}' -f $_).fa.srt"
}

# Supply content hints manually (skips auto-analysis)
Invoke-SubtitleTranslation `
    -Path 'anime.ass' `
    -ProviderName Anthropic `
    -TargetLanguage 'en' `
    -ContentType   animation `
    -ContentTitle  'Attack on Titan' `
    -ToneHint      dramatic `
    -OutputPath    'anime.en.ass'
```

### Using a Glossary

A glossary JSON file maps source terms to fixed translations that are injected into every AI prompt.

```powershell
# Build a glossary
Add-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Avengers' -Translation 'انتقام جویان'
Add-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Shield'   -Translation 'سپر'
Get-TranslationGlossary      -Path './glossary.json'
Remove-TranslationGlossaryEntry -Path './glossary.json' -SourceTerm 'Shield'

# Apply during translation
Invoke-SubtitleTranslation `
    -Path 'movie.srt' `
    -ProviderName Anthropic `
    -TargetLanguage 'fa' `
    -GlossaryPath  './glossary.json' `
    -OutputPath    'movie.fa.srt'
```

### Sessions, Caching & Resume

A session shares provider config, glossary, and result cache across multiple calls. If a run is interrupted, resume from a checkpoint file.

```powershell
$session = New-TranslationSession `
    -ProviderName   Anthropic `
    -GlossaryPath   './glossary.json' `
    -CheckpointPath './checkpoint.json'

Import-SubtitleFile 'long_ep01.srt' |
    Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session

# Resume after interruption
Import-SubtitleFile 'long_ep01.srt' |
    Invoke-SubtitleTranslation -TargetLanguage 'fa' -ProviderName Anthropic `
        -ResumeFrom './checkpoint.json' -OutputPath 'ep01.fa.srt'
```

### Progress & Live Output

Translation streams by default, so the progress bar advances **per translated line** with live token counts while a batch is still being written — rather than sitting still and then jumping once the whole batch arrives:

```
Translating to 'fa' via OpenRouter (google/gemini-3.8-flash)
Batch 3/8 | Translating 27/40 | 107/294 entries | 12.4k/~9.1k tok
  36% [###########.....................................]
```

`~` marks an estimated output-token count. OpenAI-compatible endpoints only report real usage in the final chunk of a stream, so until it arrives the figure is a characters/4 approximation rather than a measurement.

If a proxy or gateway in front of your provider does not pass server-sent events through cleanly, streaming degrades on its own — the request is simply re-sent as a normal buffered call and the translation is unaffected. To skip the attempt entirely:

```powershell
Invoke-SubtitleTranslation -Path 'movie.srt' -TargetLanguage 'fa' -ProviderName OpenRouter -NoStream
```

### Run Summary

When a translation finishes, the facts about the run itself — which are not recoverable from the subtitle file — are printed as a summary block:

```
  ────────────────────────────────────────────────────────────────────
  Translation complete
  ────────────────────────────────────────────────────────────────────
  Source    Mushoku Tensei - S03E02.srt  (SRT · UTF-8 · 294 entries)
  Output    .\Downloads\Mushoku Tensei - S03E02.fa.srt
  Language  en → fa
  Provider  OpenRouter · google/gemini-3.8-flash
  Context   animation · "Mushoku Tensei" · mixed tone   (primed)
  Glossary  14 terms

  Entries   282 translated · 12 from cache · 0 unresolved
  Requests  8 batches · 9 API calls · 1 retry · 1 truncated
  Tokens    12.4k in · 18.9k out · 31.3k total
  Elapsed   3m 41s · 80 entries/min
  Text      10,060 → 11,842 chars
  ────────────────────────────────────────────────────────────────────
```

The same data is attached to the returned object as `.TranslationSummary`, so it survives into a variable, a log, or a batch report:

```powershell
$result = Invoke-SubtitleTranslation -Path 'ep01.srt' -TargetLanguage 'fa' -ProviderName OpenRouter -OutputPath 'ep01.fa.srt'

$result.TranslationSummary.TotalTokens        # 31300
$result.TranslationSummary.UnresolvedEntries  # 0
$result.TranslationSummary.ApiCalls           # 9

# Cost a season, from the token totals of each episode
Get-ChildItem *.srt | ForEach-Object {
    (Invoke-SubtitleTranslation -Path $_ -TargetLanguage 'fa' -ProviderName OpenRouter -NoSummary).TranslationSummary
} | Measure-Object -Property TotalTokens -Sum
```

Full property list: `Provider`, `Model`, `SourceLanguage`, `TargetLanguage`, `SourcePath`, `OutputPath`, `Format`, `Encoding`, `Entries`, `TranslatedEntries`, `CachedEntries`, `UnresolvedEntries`, `SourceCharacters`, `OutputCharacters`, `Batches`, `ApiCalls`, `Retries`, `TruncatedBatches`, `InputTokens`, `OutputTokens`, `TotalTokens`, `Streaming`, `Primed`, `ContentType`, `ContentTitle`, `Tone`, `GlossaryTerms`, `Duration`, `EntriesPerMinute`, `StartedAt`, `CompletedAt`.

Use `-NoSummary` to suppress the printed block; the `.TranslationSummary` property is attached either way.

### Batch Size & Truncated Responses

Two settings control how much work goes into a single API call:

| Setting | Default | Bounds |
|---|---|---|
| `MaxTokensPerBatch` | 4000 | How much the model has to **read** (input packing, estimated at ~4 chars/token) |
| `MaxEntriesPerBatch` | 40 | How many entries the model has to **write** per call |
| `MaxOutputTokens` | 16384 | The provider's output-token cap for the response |

`MaxEntriesPerBatch` is the one worth knowing about. A short file fits the character budget whole, so without it the module would ask a model for hundreds of translated lines in a single response — which is where truncation and line-numbering drift come from.

When a response does come back short, the missing entries are automatically re-requested in progressively smaller batches, so a truncated reply repairs itself. Only if that still fails does an entry keep its source text, and you'll see:

```
WARNING: 12 of 294 entries could not be translated and kept their source text.
```

That usually means the model is running out of output budget. **Reasoning models are the common cause** — their thinking tokens are billed against `MaxOutputTokens`, so a budget that looks generous for the answer alone can be spent before the answer starts. Give it more room, or ask for less per call:

```powershell
Set-TranslationProvider -Name OpenRouter -MaxOutputTokens 32768
Set-TranslationProvider -Name OpenRouter -MaxEntriesPerBatch 20
```

OpenRouter reasoning can also be disabled for models that make reasoning optional:

```powershell
Set-TranslationProvider -Name OpenRouter -ReasoningEffort None
```

`ReasoningEffort` accepts `Auto` (the default), `None`, `Minimal`, `Low`, `Medium`, `High`, `XHigh`, or `Max`. OpenRouter models marked as having mandatory reasoning reject `None`; use `Minimal` for those, or select a non-reasoning model. `Get-TranslationProvider` shows the saved value.

### Back-Translation Verification

Re-translate back to the source language and flag entries where meaning may have been lost.

```powershell
$original   = Import-SubtitleFile 'movie.srt'
$translated = $original | Invoke-SubtitleTranslation -TargetLanguage 'fa' -ProviderName Anthropic

$report = Invoke-BackTranslation `
    -OriginalFile        $original `
    -TranslatedFile      $translated `
    -BackLanguage        'en' `
    -ProviderName        Anthropic `
    -SimilarityThreshold 0.4

$report | Where-Object { $_.Flagged } | Format-Table Index, OriginalText, BackTranslation, Similarity
```

### Post-Translation Line Wrapping

```powershell
Import-SubtitleFile 'movie.fa.srt' |
    Set-SubtitleLineWidth -MaxChars 42 -MaxLines 2 |
    Export-SubtitleFile -Path 'movie.fa.wrapped.srt'
```

---

## Batch Processing

Apply any operation to all subtitle files in a directory tree.

```powershell
# Fix encoding on every SRT file under D:\Movies
Invoke-SubtitleBatch -Path 'D:\Movies' -Recurse -Format SRT -ScriptBlock {
    $_ | Repair-SubtitleEncoding
}

# Shift all subtitles by 1 second, save with _shifted suffix
Invoke-SubtitleBatch -Path '.' -OutputSuffix '_shifted' -ScriptBlock {
    $_ | Add-SubtitleOffset -Seconds 1
}

# Translate every SRT file to Persian, log results
$session = New-TranslationSession -ProviderName Anthropic
Invoke-SubtitleBatch -Path 'D:\Shows' -Recurse -Format SRT `
    -OutputSuffix '.fa' -LogPath 'translation.log' -ScriptBlock {
    $_ | Invoke-SubtitleTranslation -TargetLanguage 'fa' -Session $session
}

# PS7+ parallel processing
Invoke-SubtitleBatch -Path 'D:\Movies' -Recurse -Parallel -ThrottleLimit 8 -ScriptBlock {
    $_ | Optimize-SubtitleFile
}
```

---

## Sharing / Publishing

Upload subtitles to [SubDL](https://subdl.com). API tokens are encrypted with Windows DPAPI and persist across sessions.

```powershell
# Store your SubDL API token
Set-SubDLCredential -ApiToken 'your-subdl-token'

# Verify it's stored
Get-SubDLCredential

# Upload a subtitle file
Publish-SubtitleFile -Path 'movie.fa.srt' -Language 'FA' -ImdbId 'tt1234567'

# Upload via pipeline
Import-SubtitleFile 'movie.fa.srt' | Publish-SubtitleFile -Language 'FA' -ImdbId 'tt1234567'

# Remove stored token
Remove-SubDLCredential
```

---

## Utilities

```powershell
# Summary of a subtitle file
Get-SubtitleInfo -Path 'movie.srt'

# Find all subtitle files recursively
Find-SubtitleFile -Path 'D:\Movies' -Recurse

# Find only ASS files matching a pattern
Find-SubtitleFile -Path 'D:\Anime' -Format ASS -Pattern '*english*' -Recurse

# Compare original and translated files side by side
Compare-SubtitleFile -Reference $original -Difference $translated | Format-Table

# Deduplicate, sort, trim whitespace
Import-SubtitleFile 'messy.srt' | Optimize-SubtitleFile | Export-SubtitleFile -Path 'clean.srt'
```

---

## All Functions

| Category | Functions |
|----------|-----------|
| **Core I/O** | `Import-SubtitleFile` · `Export-SubtitleFile` · `ConvertFrom-SrtFile` · `ConvertTo-SrtFile` · `ConvertFrom-AssFile` · `ConvertTo-AssFile` |
| **Validation** | `Test-SrtFile` · `Test-AssFile` · `Test-SubtitleTimestamps` · `Test-SubtitleOverlap` |
| **Repair** | `Repair-SrtFile` · `Repair-AssFile` · `Repair-SubtitleEncoding` · `Repair-SubtitleOverlap` · `Repair-SubtitleNumbering` |
| **Timestamps** | `Add-SubtitleOffset` · `Set-SubtitleOffset` · `Get-SubtitleDuration` · `Set-SubtitleDuration` · `Invoke-SubtitleStretch` · `Merge-SubtitleFile` · `Split-SubtitleFile` |
| **ASS Advanced** | `Get-AssStyle` · `Set-AssStyle` · `New-AssStyle` · `Remove-AssStyle` · `Remove-AssOverrideTag` · `Convert-AssToPlainText` · `Convert-AssToSrt` · `Convert-SrtToAss` |
| **AI Translation** | `Set-TranslationProvider` · `Get-TranslationProvider` · `Remove-TranslationProvider` · `New-TranslationSession` · `Invoke-SubtitleTranslation` · `Invoke-BackTranslation` · `Get-OpenRouterModel` · `Get-TranslationGlossary` · `Add-TranslationGlossaryEntry` · `Remove-TranslationGlossaryEntry` · `Set-SubtitleLineWidth` |
| **Batch & Utilities** | `Get-SubtitleInfo` · `Find-SubtitleFile` · `Compare-SubtitleFile` · `Optimize-SubtitleFile` · `Invoke-SubtitleBatch` |
| **Sharing** | `Publish-SubtitleFile` · `Set-SubDLCredential` · `Get-SubDLCredential` · `Remove-SubDLCredential` |

Use `Get-Help <FunctionName> -Full` for complete parameter documentation and examples.  
Use `Get-Help about_SubtitleTools` for a module overview.

---

## Requirements

- **PowerShell 5.1** (Windows PowerShell) or **PowerShell 7+**
- **Windows** — API key encryption uses Windows DPAPI (tied to your user account)
- **No external module dependencies** — HTTP calls use built-in `Invoke-RestMethod`
- AI translation requires API keys for the provider(s) you want to use

---

## Contributing

Issues and pull requests are welcome at [github.com/imanedr/SubtitleTools](https://github.com/imanedr/SubtitleTools).

---

## License

MIT — see [LICENSE](LICENSE) for details.  
Copyright (c) 2025 Iman Edrisian.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full history of notable changes to this project.
