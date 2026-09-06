# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
