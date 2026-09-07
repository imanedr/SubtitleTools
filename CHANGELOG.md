# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-09-06

### Added

- **End-of-run translation summary.** A finished translation returned a
  `SubtitleFile` and nothing else, so everything the run had learned — which
  provider and model actually served it, how many entries came from cache,
  how many were left untranslated, how many API calls and retries it took,
  what it cost in tokens, how long it ran — was discarded the moment the
  function returned. That information is now collected into a
  `SubtitleTools.TranslationSummary` object, printed as a summary block and
  attached to the returned file as `.TranslationSummary`:

  ```powershell
  $result = Invoke-SubtitleTranslation -Path 'ep01.srt' -TargetLanguage 'fa' -ProviderName OpenRouter
  $result.TranslationSummary.TotalTokens
  $result.TranslationSummary.UnresolvedEntries
  ```

  The printed block degrades to ASCII glyphs when the console is not UTF-8, so
  it stays readable on a legacy Windows PowerShell host.
- `-NoSummary` on `Invoke-SubtitleTranslation`, which suppresses the printed
  block only. The `.TranslationSummary` property is attached either way.

### Changed

- **`SubtitleFile` now has display formatting** (`SubtitleTools.format.ps1xml`,
  registered through the manifest's `FormatsToProcess`). Previously it rendered
  by dumping every property, including the whole `Entries` array, so importing
  or translating a 300-line subtitle answered with a screenful of truncated
  dialogue rather than a description of the file. It now shows path, format,
  encoding, entry count, total duration, parser-warning count, and — when
  present — a one-line translation summary. No property is hidden; they all
  remain directly accessible and `Format-List *` still shows everything.
- `Invoke-BackTranslation` passes `-NoSummary` to its internal back-translation
  pass, so a verification run no longer prints a "Translation complete" block
  for work the caller did not ask for directly.

## [1.2.0] - 2026-09-06

### Fixed

- **Long files were silently translated only part-way.** A 294-entry episode
  sent to `google/gemini-3.8-flash` via OpenRouter came back translated up to
  entry 76; entries 77-294 were written out as untranslated source text with
  no error. Three things combined to produce that:
  - Batches were sized purely by character budget (`MaxTokensPerBatch * 4`
    chars). A short file fits that budget whole, so all 294 entries went out
    as a *single* call asking the model for 294 translated lines.
  - `MaxOutputTokens` defaulted to 8192. On a reasoning model the thinking
    tokens are billed against that same budget, so generation stopped before
    the answer was finished.
  - The truncated reply was an HTTP 200 carrying `finish_reason: "length"`.
    `FinishReason` was only ever compared against `'error'`, so truncation was
    invisible and the missing entries took the "not in the response" path,
    which quietly substituted source text.

  Truncation is now detected across all providers' spellings of it
  (`length`, `max_tokens`, `MAX_TOKENS`), and any entries a response fails to
  return are re-requested in progressively smaller batches rather than given
  up on. Falling back to source text is now a last resort and reports itself
  on the warning stream, not only in the log file.
- **Untranslated fallback text was written to the translation cache**, which
  made it a permanent cache hit — so neither re-running the file nor resuming
  from a checkpoint could ever repair the affected entries.
- **A truncated response's last line is now discarded** rather than kept.
  Generation stops mid-token, so that line can be a half-written sentence.

### Added

- **Streaming translation with live progress.** Translation requests now use
  server-sent events by default, so the progress bar advances per translated
  line and the token counters tick upward *while* a batch is being written,
  instead of jumping only once the whole batch lands. Supported on all four
  providers. Implemented on `HttpClient` so it works on Windows PowerShell 5.1
  and PowerShell 7 alike, and any streaming failure falls back to the previous
  buffered request — streaming is never why a translation fails. Use
  `-NoStream` on `Invoke-SubtitleTranslation` to opt out (e.g. behind a proxy
  that does not pass SSE through).
- **`MaxEntriesPerBatch` provider setting** (default 40). Caps how many
  entries go into one API call, bounding what the model has to *write* rather
  than only what it has to read. This is the structural fix for the
  one-giant-batch problem above, and it also gives a long file many more
  progress updates.

### Changed

- Default `MaxOutputTokens` raised from 8192 to 16384, since reasoning models
  spend part of that budget on thinking tokens.
- Batches are now planned up front, so progress reports a real `Batch 3/8`
  denominator instead of an open-ended count.

## [1.1.0] - 2026-09-06

### Added

- **OpenRouter provider.** A fourth translation provider giving access to
  hundreds of hosted models behind one OpenAI-compatible endpoint, plus a new
  `Get-OpenRouterModel` function for browsing the catalogue (context length,
  output cap, and per-million-token pricing) before configuring a provider.
- **`MaxOutputTokens` provider setting.** The API output-token cap (e.g.
  Anthropic's `max_tokens`) is now configurable and distinct from
  `MaxTokensPerBatch`, which is only ever a client-side heuristic for packing
  entries into a batch. Previously Anthropic hardcoded 8192 and OpenAI/Google
  sent no cap at all, which could truncate translations into languages that
  expand relative to the source.
- **Richer progress reporting.** Priming (the content-analysis pass run
  before translation) now reports as a visible nested phase instead of only
  `Write-Verbose`, so a run no longer looks like it's hanging while it makes
  that first API call. Running totals for input/output tokens and retry
  counts are now surfaced in the progress bar and closing summary. Progress
  bars from nested commands (e.g. `Invoke-BackTranslation` calling
  `Invoke-SubtitleTranslation`, or translation running inside
  `Invoke-SubtitleBatch`) now nest via `-Id`/`-ParentId` instead of
  overwriting each other, and file logging routes through the shared
  `Write-SubtitleLog` helper instead of a hand-rolled log writer.

### Fixed

- **PowerShell 5.1 could not import the module at all.** The `??`
  null-coalescing operator (a PowerShell 7+ feature) was used 11 times in the
  translation code. Because the module dot-sources every source file
  unconditionally, that single parse error broke `Import-Module` for the
  *entire* module on Windows PowerShell 5.1 — every single one of its
  functions — not just translation. `ConvertFrom-Json -AsHashtable` (also
  PowerShell 6+ only) was fixed the same way in four other files.
- **The module silently exported zero functions on Linux and macOS.** The
  module loader built file paths with backslashes, which match nothing on
  non-Windows filesystems, and the failure was swallowed by
  `-ErrorAction SilentlyContinue`, so `Import-Module` appeared to succeed
  with an empty module. Config-file paths had the same problem, and
  `Join-Path $env:APPDATA` threw outright since `APPDATA` doesn't exist off
  Windows. Paths are now built with `Join-Path` throughout, and the config
  root resolves per-platform (`APPDATA` on Windows, `XDG_CONFIG_HOME` or
  `~/.config` elsewhere), preserving existing saved providers on Windows.
  DPAPI-based credential storage remains Windows-only by design, but now
  throws a clear explanation instead of an opaque
  `PlatformNotSupportedException`.
- **`Invoke-BackTranslation` was completely unusable.**
  `Invoke-SubtitleTranslation`'s `-OutputPath` parameter was marked
  `Mandatory`, but `Invoke-BackTranslation` never passes it — every call
  failed.
- **A safety-filtered Google prompt returned garbage as translated text.**
  The Google adapter called `.ToLower()` on a `finishReason` value that is
  absent when a prompt is blocked by safety filters. That threw inside a
  `try` block, was swallowed as a retryable error, and after exhausting
  retries returned a raw .NET exception string as if it were the translated
  subtitle text. The block reason is now surfaced as a clear, non-retryable
  error instead.
- **Other HTTP-layer bugs fixed by centralizing request handling** into a
  shared `Invoke-TranslationApiRequest` helper (previously each of the three
  adapters carried its own near-identical, independently-buggy retry loop):
  - `Content-Type` was sent via `-Headers`, which throws on Windows
    PowerShell 5.1 Desktop where it's a restricted header.
  - HTTP error response bodies were discarded in favor of a generic message,
    so an invalid API key surfaced as `"(401) Unauthorized"` instead of the
    provider's actual explanation.
  - Permanent 4xx failures (bad key, bad request, not found) were retried
    with backoff up to three times instead of failing fast; only 429, 5xx,
    and network errors are retried now.
  - Request bodies were not reliably encoded as UTF-8 on Desktop, which could
    corrupt non-ASCII subtitle text.
  - The Anthropic adapter assumed `content[0]` was always the text block; it
    now selects the first `text`-typed block and errors clearly if none
    exists.
  - The Google adapter sent the API key in the URL query string, where it
    could leak into exception messages and logs; it now uses the
    `x-goog-api-key` header.
- **`Set-TranslationProvider`'s update-detection heuristic** counted bound
  parameters to decide whether an update was requested, so any bound common
  parameter (e.g. `-Verbose`) would incorrectly trigger an update path. It
  now checks for actual configuration parameters.
- **A mid-run batch failure discarded the whole translation.** A checkpoint
  was only saved on successful completion, so a failure partway through a
  long run threw away every batch already translated — exactly when a
  checkpoint matters most. The checkpoint is now saved before the failure is
  rethrown.

### Changed

- Module source moved from a version-named `1.0.0/` subfolder to the repo
  root; the module version now lives solely in the manifest's
  `ModuleVersion` field, so a release no longer requires renaming a
  directory.
- Provider name validation (`OpenAI`/`Anthropic`/`Google`/`OpenRouter`) is
  kept consistent across all public functions, provider defaults, and docs
  now that a fourth provider exists.

## [1.0.0] - 2026-05-25

### Added

- Parse and serialize SRT and ASS/SSA files with full round-trip fidelity.
- Validation: block structure, timestamps, overlapping entries.
- Repair: numbering, encoding (UTF-16/Windows-1252 → UTF-8), timestamp
  separators, overlaps.
- Timestamp manipulation: shift, stretch (two-point sync), merge, split.
- ASS/SSA: style CRUD, override tag stripping, format conversion
  (SRT ↔ ASS).
- AI translation via OpenAI, Anthropic, and Google APIs with batching,
  caching, glossary, content-aware priming, back-translation verification,
  and resume from checkpoint.
- Batch processing: apply any operation to an entire directory tree
  (PS7+ parallel support).
- Subtitle publishing to SubDL.
- No external dependencies; API keys encrypted with Windows DPAPI.
