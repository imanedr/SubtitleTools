# SubtitleTools — Module Design & Architecture

**Author:** Iman Edrisian  
**Version:** 1.3.2 \
**Target:** PowerShell 5.1+ (Desktop & Core)

---

## Overview

SubtitleTools is a PowerShell module for working with subtitle files in SRT and ASS/SSA formats. It covers the full lifecycle: reading, validating, repairing, manipulating timestamps, converting between formats, and translating via AI provider APIs.

---

## Directory Structure

```
SubtitleTools/
├── SubtitleTools.psd1          # Module manifest
├── SubtitleTools.psm1          # Root loader — classes defined here, functions dot-sourced
├── SubtitleTools.format.ps1xml # Display views for SubtitleFile and TranslationSummary
├── DESIGN.md                   # This file
├── README.md                   # User-facing documentation
├── CHANGELOG.md                # Keep a Changelog-format release history
│
├── Public/                     # Exported functions (visible to module consumers)
│   ├── Core/                   # I/O: Import, Export, ConvertFrom/To
│   ├── Validation/             # Test-* functions
│   ├── Repair/                 # Repair-* functions
│   ├── Timestamps/             # Offset, duration, stretch, merge, split
│   ├── ASS/                    # ASS-specific: styles, tag stripping, format conversion
│   ├── Translation/            # AI translation, glossary, back-translation, line width
│   └── Utilities/              # Info, find, compare, optimize, batch
│
├── Private/                    # Internal helpers (not exported)
│   ├── Parsers/                # Invoke-SrtParser, Invoke-AssParser
│   ├── Writers/                # Write-SrtEntry, Write-AssEntry, Write-AssHeader
│   ├── Encoding/               # Get-FileEncoding, Remove-ByteOrderMark, ConvertTo-NormalizedText
│   ├── Sharing/                # Invoke-SubDLUpload, SubDLTokenStore, ConvertTo-MultipartFormBody
│   ├── Translation/            # Invoke-AnthropicTranslation, Invoke-OpenAITranslation, Invoke-GoogleTranslation,
│   │                           # Invoke-OpenRouterTranslation, Invoke-TranslationApiRequest (shared HTTP helper),
│   │                           # Invoke-TranslationProviderAdapter (dispatch), Invoke-TranslationPriming,
│   │                           # Invoke-TranslationApiStream (SSE), Invoke-TranslationBatchRequest (recovery),
│   │                           # Build-TranslationSystemPrompt, Write-TranslationSummary, ProviderStore
│   └── Utilities/              # Timestamp converters, Write-SubtitleLog, New-SubtitleEntryCopy
│
├── Data/                       # Reference JSON data loaded at module import
│   ├── ProviderDefaults.json   # Default model/URL/rate-limit per AI provider
│   ├── LanguageCodes.json      # BCP-47 code -> language name map
│   └── DefaultAssStyles.json   # Factory ASS style templates
│
└── Tests/
    ├── Unit/                   # Pester 5 unit tests
    └── Fixtures/               # Sample .srt and .ass files for testing
```

---

## Key Design Decisions

### 1. Classes defined in the root psm1

PowerShell 5.1 limitation: classes defined in dot-sourced `.ps1` files inside a module are not accessible to callers that use `Import-Module`. They would only be available via `using module`. To remain compatible with `Import-Module`, all class definitions are written directly in `SubtitleTools.psm1`. The separate `Classes/` files serve as reference copies.

### 2. Timestamps stored as `[TimeSpan]`

All timestamps are held internally as `[TimeSpan]`. Serialization to format-specific strings happens only at parse and write boundaries:

| Format | String form | Parsed by | Serialized by |
|--------|-------------|-----------|---------------|
| SRT | `HH:mm:ss,fff` | `ConvertFrom-SrtTimestamp` | `ConvertTo-SrtTimestamp` |
| ASS | `H:mm:ss.cc` (centiseconds) | `ConvertFrom-AssTimestamp` | `ConvertTo-AssTimestamp` |

This means all timestamp arithmetic (offsets, stretch, overlap detection) works uniformly regardless of source format.

### 3. Translation — Provider Adapter Pattern

One public function (`Invoke-SubtitleTranslation`) dispatches to private adapter scripts. Adding a new provider requires only a new file in `Private/Translation/`.

**Adapter contract:**

```
Input:
    [string]            $SystemPrompt
    [string]            $UserContent
    [TranslationProvider] $Provider
    [SecureString]      $ApiKey

Output: [PSCustomObject]
    .Content       [string]   Raw response text
    .InputTokens   [int]
    .OutputTokens  [int]
    .FinishReason  [string]   'stop' | 'length' | 'error'
    .Model         [string]
```

**Batch packing:** entries are grouped into batches bounded by *two* limits, and the batch plan is computed up front so progress can report a real `Batch 3/8`:

- `MaxTokensPerBatch * 4` characters (1 token ≈ 4 chars) — an *input* heuristic.
- `MaxEntriesPerBatch` entries (default 40) — an *output* bound.

The second limit matters more than it looks. A short file fits the character budget whole, so without an entry cap the module would ask a model for several hundred translated lines in one response — which invites both output truncation and line-numbering drift. `MaxEntriesPerBatch` is what keeps a single response to a size models reliably complete.

Within each batch, entries are sent as numbered lines (`N|text`) and intra-entry line breaks are encoded as `<NL>`. The response is parsed by splitting on the first pipe only, validated by index.

**Recovering an incomplete response** (`Invoke-TranslationBatchRequest`): entries the response fails to return are not written off. They are re-requested, halving the request at each level up to `MaxSplitDepth` (default 3). This covers the two ways a response comes back short:

- *Truncation.* The model hit its output-token cap. On a reasoning model the thinking tokens are billed against that same cap, so a budget sized for the visible answer alone can be exhausted before the answer starts. Providers spell this three different ways (`length`, `max_tokens`, `MAX_TOKENS`) — `Test-TranslationTruncated` normalises them. Critically, a truncated response is an HTTP 200, so nothing throws and it must be checked for explicitly. The last parsed line of a truncated response is also discarded, since generation stopped mid-token and that line may be half-written.
- *Numbering drift.* On a long numbered list a model can skip, duplicate, or renumber lines.

Only after the retries are exhausted does an entry fall back to source text — and that is reported on the warning stream, because a partially translated subtitle file opens and plays normally and nothing else would reveal it. Fallback text is deliberately **not** cached: caching it would make it a permanent cache hit that no re-run or checkpoint resume could repair.

**Streaming** (`Invoke-TranslationApiStream`): translation calls use server-sent events by default, so the caller can report progress while the model is still writing rather than only when the batch lands. Built on `System.Net.Http.HttpClient` with `ResponseHeadersRead` — the one HTTP client that can hand back a response stream before the body completes on *both* Windows PowerShell 5.1 Desktop and PowerShell 7 (`Invoke-RestMethod` buffers on both). Each provider's event schema is decoded by `-Shape` (`OpenAI` covers OpenRouter too). `Invoke-TranslationStreamAttempt` owns the degradation policy: a 4xx other than 429 is reported as an error, while 429/5xx and any transport failure return `$null` so the caller falls back to the buffered path. Streaming is a progress nicety and is never allowed to be the reason a translation fails; `-NoStream` disables it outright.

**Run summary** (`Write-TranslationSummary`): the facts about a run — provider and model, batches, API calls, retries, truncated batches, tokens in/out, how many entries came from cache, how many never resolved, elapsed time — exist only in `Invoke-SubtitleTranslation`'s local variables and are unrecoverable from the translated file. They are therefore collected into a `SubtitleTools.TranslationSummary` object, attached to the returned `SubtitleFile` as `.TranslationSummary`, and rendered as a console block (suppressed by `-NoSummary`). The object is the source of truth; the block is one rendering of it. The renderer is the module's only sanctioned `Write-Host` — an end-of-run report for a human, where writing to the output stream would corrupt the `SubtitleFile` being returned — and it falls back to ASCII glyphs unless `[Console]::OutputEncoding` is UTF-8, since a legacy Windows console turns box-drawing characters into mojibake.

**Display formatting** (`SubtitleTools.format.ps1xml`, loaded via the manifest's `FormatsToProcess`): without it a returned `SubtitleFile` renders by dumping every property including the entire `Entries` array, so translating a 300-line subtitle answered with a wall of truncated dialogue. The list views summarise `SubtitleFile` and `SubtitleTools.TranslationSummary` instead. Nothing is hidden — every property stays accessible, and `Format-List *` still shows them all.

**Rate limiting:** a sliding window tracks requests per minute per session. When `RateLimitRpm` is approached, the function sleeps until the window resets.

**Caching:** each entry's text is MD5-hashed. Translated text is stored in `$Session.Cache` keyed by hash. A checkpoint file can persist the cache across interrupted runs (`-ResumeFrom`).

### 4. API Key storage

No keys are ever stored in plain text. Keys are encrypted with **Windows DPAPI** (`System.Security.Cryptography.ProtectedData`, `CurrentUser` scope) and stored as Base64 in `%APPDATA%\SubtitleTools\providers.json` alongside the rest of the provider config (model, base URL, rate limit, etc.). The file is per-user and cannot be decrypted on another machine or by another Windows account. `Protect-ApiKey` / `Unprotect-ApiKey` / `Save-ProviderStore` in `Private/Translation/ProviderStore.ps1` own this logic. There are no external dependencies — no SecretManagement vault is required.

### 5. Encoding detection (private `Get-FileEncoding`)

Detection order:
1. BOM bytes — `EF BB BF` (UTF-8 BOM), `FF FE` (UTF-16 LE), `FE FF` (UTF-16 BE), `FF FE 00 00` (UTF-32 LE)
2. Attempt UTF-8 decode; check for `U+FFFD` replacement character
3. Fall back to Windows-1252 (most common legacy encoding for Western subtitles)
4. Final fallback: ISO-8859-1

Export always defaults to UTF-8 without BOM. Override with `-Encoding` on `Export-SubtitleFile`.

---

## Class Hierarchy

```
SubtitleEntry           (base)
├── SrtEntry            BlockNumber, HasHtmlTags
└── AssEntry            Layer, Style, Name, MarginL/R/V, Effect, EventType, OverrideTags

SubtitleFile            Path, Format, Encoding, HasBom, Header, Entries[], ParserWarnings
AssHeader               ScriptType, Title, PlayResX/Y, ExtraFields, Styles[], EventColumnOrder[]
AssStyle                Full ASS v4+ style fields + ToAssLine() serializer
ValidationResult        IsValid, Errors[], Warnings[], AddError(), AddWarning()
ValidationIssue         EntryIndex, Field, Message, Severity
TranslationProvider     Name, Model, ApiKeyEncrypted, BaseUrl, RateLimitRpm, Temperature
```

---

## Public Function Reference

### Core I/O

| Function | Description |
|----------|-------------|
| `Import-SubtitleFile` | Auto-detect format & encoding; return `SubtitleFile` |
| `Export-SubtitleFile` | Write `SubtitleFile` to disk (UTF-8 no-BOM default) |
| `ConvertFrom-SrtFile` | Parse SRT string or file to `SrtEntry[]` |
| `ConvertTo-SrtFile` | Serialize `SubtitleFile` / `SrtEntry[]` to SRT string |
| `ConvertFrom-AssFile` | Parse ASS/SSA string or file to `SubtitleFile` |
| `ConvertTo-AssFile` | Serialize `SubtitleFile` to ASS string |

### Validation

| Function | Description |
|----------|-------------|
| `Test-SrtFile` | Validate block numbering, timestamps, text; return `ValidationResult` |
| `Test-AssFile` | Validate sections, styles, column counts, override tags |
| `Test-SubtitleTimestamps` | Check all entries have end > start, no negatives |
| `Test-SubtitleOverlap` | Detect entries that start before the previous one ends |

### Repair

| Function | Description |
|----------|-------------|
| `Repair-SrtFile` | Renumber, normalize delimiters, remove BOM, drop empty entries |
| `Repair-AssFile` | Add missing header/styles, close unclosed override tags |
| `Repair-SubtitleEncoding` | Re-encode to UTF-8 without BOM |
| `Repair-SubtitleOverlap` | Resolve overlaps: `Trim` / `Shift` / `Drop` strategy |
| `Repair-SubtitleNumbering` | Renumber SRT block numbers sequentially from 1 |

### Timestamps

| Function | Description |
|----------|-------------|
| `Add-SubtitleOffset` | Shift all (or a range of) entries by a `TimeSpan` / ms / s / min |
| `Set-SubtitleOffset` | Set anchor entry's start time; shift all others by the same delta |
| `Get-SubtitleDuration` | Return duration statistics (total span, avg, min, max) |
| `Set-SubtitleDuration` | Clamp/extend entry durations to min/max `TimeSpan` |
| `Invoke-SubtitleStretch` | Linear two-point time-stretch to correct A/V drift |
| `Merge-SubtitleFile` | Interleave two files sorted by start time |
| `Split-SubtitleFile` | Split by timestamp or chunk size |

### ASS Advanced

| Function | Description |
|----------|-------------|
| `Get-AssStyle` | List all or a named style from an ASS file |
| `Set-AssStyle` | Update style properties by name |
| `New-AssStyle` | Create a style and optionally add it to a file |
| `Remove-AssStyle` | Remove a style; reassigns affected entries to Default |
| `Remove-AssOverrideTag` | Strip `{\...}` tags (all or by regex pattern) |
| `Convert-AssToPlainText` | Strip all tags, convert `\N` to newlines |
| `Convert-AssToSrt` | Convert ASS → SRT (maps `{\i1}` → `<i>` etc.) |
| `Convert-SrtToAss` | Convert SRT → ASS (maps `<i>` → `{\i1}` etc.) |

### Translation

| Function | Description |
|----------|-------------|
| `Set-TranslationProvider` | Configure a provider; encrypts API key with DPAPI and persists to `providers.json` |
| `Get-TranslationProvider` | List configured providers and key status |
| `Remove-TranslationProvider` | Remove a saved provider |
| `New-TranslationSession` | Create a session with provider, glossary, and cache |
| `Invoke-SubtitleTranslation` | Translate a file; batch, cache, rate-limit, resume, live progress, run summary |
| `Invoke-BackTranslation` | Re-translate to source language; flag low-similarity entries |
| `Get-OpenRouterModel` | List models available via the OpenRouter API (id, context length, pricing) |
| `Get-TranslationGlossary` | Read a glossary JSON file |
| `Add-TranslationGlossaryEntry` | Add / update a glossary term |
| `Remove-TranslationGlossaryEntry` | Remove glossary terms by name or wildcard |
| `Set-SubtitleLineWidth` | Wrap lines to max characters (default 42) and max line count |

### Sharing / Publishing

| Function | Description |
|----------|-------------|
| `Set-SubDLCredential` | Encrypt and persist a SubDL API token (DPAPI) |
| `Get-SubDLCredential` | Check whether a SubDL token is stored |
| `Remove-SubDLCredential` | Delete the stored SubDL token |
| `Publish-SubtitleFile` | Upload subtitle to SubDL via REST API |

### Utilities

| Function | Description |
|----------|-------------|
| `Get-SubtitleInfo` | One-line summary: format, count, encoding, overlaps, duration |
| `Find-SubtitleFile` | Recursive file search filtered by format and filename pattern |
| `Compare-SubtitleFile` | Side-by-side diff of two files (timestamps + text) |
| `Optimize-SubtitleFile` | Sort, deduplicate, trim whitespace, normalize Unicode |
| `Invoke-SubtitleBatch` | Apply a scriptblock to all files in a directory with progress |

---

### 6. Subtitle Publishing — SubDL

`Publish-SubtitleFile` uploads to SubDL via their REST API.

Token storage follows the same DPAPI pattern as translation providers:
- Module-scope: `$script:SubDLTokenEncrypted`, `$script:SubDLTokenStorePath`
- Persisted to: `%APPDATA%\SubtitleTools\subdl.json`
- Managed by: `Private/Sharing/SubDLTokenStore.ps1` (`Protect-SubDLToken`, `Unprotect-SubDLToken`, `Save-SubDLTokenStore`)

**Public functions:**

| Function | Description |
|----------|-------------|
| `Set-SubDLCredential` | Encrypt and persist a SubDL API token |
| `Get-SubDLCredential` | Check whether a token is stored |
| `Remove-SubDLCredential` | Delete the stored token |
| `Publish-SubtitleFile` | Upload a subtitle file to SubDL |

**SubDL adapter (`Private/Sharing/Invoke-SubDLUpload.ps1`):** three sequential calls against `api3.subdl.com` — `GET /user/getNId` for a session id, `POST /user/uploadSingleSubtitle` for the file itself, `POST /user/uploadSubtitle` for the metadata. Auth is a bearer token header, not a form field. Language codes resolved via `$script:SubDLLanguages` from `Data/SubDLLanguages.json`.

Both POSTs are `multipart/form-data`, built by `Private/Sharing/ConvertTo-MultipartFormBody.ps1` and sent as a `[byte[]]` through `-Body`. `Invoke-RestMethod -Form` would be the obvious way to do this and is what the code originally used, but it is **PowerShell 6.1+** — on the 5.1 host this module claims to support it fails parameter binding outright, so `Publish-SubtitleFile` could not work there at all. Both editions now take the hand-built path rather than branching on version: an edition-specific branch that the maintainer cannot execute is one that rots untested. The body is accumulated in a `MemoryStream`, not concatenated as a string, so a subtitle's own bytes — a BOM, UTF-16, a stray `0x00`, a bare `LF` that must not become `CRLF` — reach the server unaltered.

---

## Phased Roadmap (completed)

| Version | Theme |
|---------|-------|
| v1.0 | Core parse/serialize, validation, repair, encoding, basic timestamps |
| v1.1 | Advanced timestamps (stretch, merge, split), compare, optimize, find |
| v1.2 | ASS style CRUD, tag stripping, SRT↔ASS format conversion |
| v1.3 | Batch processing (`Invoke-SubtitleBatch`), `Write-Progress`, `-LogPath` |
| v2.0 | AI translation — OpenAI, Anthropic, Google; batching, caching, rate-limiting, checkpoints, glossary |
| v2.1 | Back-translation verification, glossary CRUD, `Set-SubtitleLineWidth` |

---

## External Dependencies

This module has **no runtime external dependencies**. API keys are encrypted with Windows DPAPI and stored locally — no SecretManagement vault is required.

| Module | Purpose | Required for |
|--------|---------|--------------|
| `Pester` 5.x | Test framework | Development only |

HTTP calls use the built-in `Invoke-RestMethod` — no extra HTTP client module needed.
