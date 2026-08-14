# MediaPrep MKV Toolkit

PowerShell toolkit for preparing, muxing, analyzing, organizing, and optionally re-encoding video files to MKV.

**Current release build: 0.11.54**

[Download the latest packaged release](https://github.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases/latest)

> **License:** MediaPrep MKV Toolkit is free/open-source software licensed under **GPL-3.0-or-later**. External tools and codec implementations keep their own licenses. See [LICENSE.md](LICENSE.md), [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md), and [ENCODER-LICENSING.md](ENCODER-LICENSING.md).

## 0.11.54 final

- Promotes the validated beta 12 codebase to the 0.11.54 release without changing mux, queue, encoder, classification, subtitle-language, or CPU/GPU behavior.
- Ships 14 validated interface languages using schema 1 / `LanguageFileVersion` 1.7.5 / 739 synchronized keys.
- Includes the GPL-3.0-or-later project license plus separate third-party and encoder/codec licensing documentation.
- Retains restart-safe UNC staging, error-queue handling, per-file statistics/classification, subtitle-language selection/filename override, and the verified HEVC encoder paths.
- Includes the corrected language validator with case-sensitive mojibake detection.
- The published GitHub release should be tested end-to-end from a real 0.11.53 installation, including automatic restart after the updater completes.

## 0.11.54 beta 12 test focus

- Fixes a false-positive mojibake warning in `App\Test-MediaPrepLanguages.ps1` by making the mojibake regex case-sensitive (`-cmatch`).
- Legitimate lowercase accented characters such as French `â` no longer match uppercase mojibake signatures such as `Â...`.
- Language resources remain unchanged from beta 11: schema 1 / LanguageFileVersion 1.7.5 / 739 keys across all 14 languages.
- No mux, queue-processing, Dashboard, encoding, classification, subtitle-language or CPU/GPU layout logic was intentionally changed.

## 0.11.54 beta 11 test focus

- Dashboard localization polish: all tabs, grid headers, buttons and summary captions are explicitly reapplied from the selected language after the window is constructed.
- The Dashboard watches the saved language preference and can refresh its UI language without leaving a mixed-language window.
- Slow-copy direction values (`In` / `Out`) are now localized.
- No mux, queue-processing, encoding, classification or CPU/GPU layout logic was intentionally changed.

## 0.11.54 beta 10 test focus

- Freezes `en-US` as the authoritative 0.11.54 localization master: schema 1 / LanguageFileVersion 1.7.4 / 737 keys.
- Ships 14 validated interface language resources: English, Swedish, German, French, Spanish, Italian, Finnish, Norwegian Bokmål, Danish, Icelandic, Dutch, Simplified Chinese, Hindi, and Bengali.
- Every locale has the same key count/order and format placeholders as en-US and is stored as UTF-8 with BOM for Windows PowerShell 5.1 compatibility.
- Adds a frozen-master SHA-256 record under `Languages\MASTER-en-US-0.11.54.sha256` so accidental edits to the 0.11.54 English master are easy to detect.
- Language discovery remains dynamic; no hard-coded 14-language list was added to the Start Center. Valid locale JSON files are discovered automatically.
- This beta is localization-only apart from build markers/documentation. Muxing, queue/UNC behavior, subtitle handling, classification/ratios, encoding, Dashboard logic, and the CPU/GPU layout are unchanged from beta 9.

## 0.11.54 beta 9 test focus

- Changes the MediaPrep source-code license from the previous personal/non-commercial terms to **GNU GPL version 3 or any later version (GPL-3.0-or-later)**.
- Includes the complete GPLv3 text in `LICENSE`, a concise project notice in `LICENSE.md`, and SPDX `GPL-3.0-or-later` identifiers in shipped PowerShell/CMD source files.
- Adds `THIRD-PARTY-LICENSES.md` and `ENCODER-LICENSING.md` so the MediaPrep license, external-tool licenses, hardware API licenses and codec/patent questions are not mixed together.
- Documents the current Gyan FFmpeg essentials download path as a GPLv3 Windows build and records that the MediaPrep ZIP itself does not bundle FFmpeg/ffprobe/MKVToolNix binaries.
- Records AV1/libaom as the preferred first future codec/encoder candidate for lower royalty-policy friction, but **does not change the working HEVC encoder pipeline in beta 9**.
- Fixes `App\Test-MediaPrepLanguages.ps1` for Windows PowerShell 5.1 by resolving the repository root after `param(...)` binding instead of using `$PSScriptRoot` inside a default parameter expression, and prevents the validator from falsely detecting its own `Msg(...)` test string as legacy localization.
- Localization resources remain schema 1 / language-file version 1.7.4 with the same 737 `en-US` / `sv-SE` keys. No translation set is generated yet.

## 0.11.54 beta 8 test focus

- Completes the localization audit before the full translation set is generated. Normal user-facing text is centralized in the common locale JSON resources across Start Center, the processing engine, Queue Dashboard, queue console, tool/version manager, encoder test, updater, local installer, web installer, and early startup paths.
- `en-US` is the authoritative master/fallback and `sv-SE` is kept in exact lockstep. Both files use schema 1, `LanguageFileVersion = 1.7.4`, UTF-8 with BOM, identical key order, identical placeholders, and 737 keys.
- Language JSON remains flat, but is arranged in logical blocks with alphabetical keys inside each block so future translations are easier to review and diff.
- Adds `App\Test-MediaPrepLanguages.ps1`, which validates BOM/JSON/schema/version/culture, exact key count and order, placeholders, empty translations, mojibake patterns, missing source references, and legacy `Msg(...)` localization.
- Technical diagnostics intended for troubleshooting may remain in English. Internal status codes, established report filenames, codec/container names, executable names, and product/version labels are not translated.
- Only `en-US` and `sv-SE` are shipped in beta 8. The additional planned language files are deliberately postponed until this master text set has passed beta testing and is frozen.
- Processing behavior from beta 7 is intentionally unchanged: muxing, queue isolation, subtitle-language handling, TV/Film/Other classification, ratios, error handling, and CPU/GPU layout are regression-test targets only.

## 0.11.54 beta 7 test focus

- Restores UNC import/mux after the subtitle-language implementation exposed a Windows PowerShell generic-list binder problem.
- Subtitle language discovery/matching uses `.Count` / `.ToArray()` instead of `@(...)` around `New-Object System.Collections.Generic.List[object]`.
- Empty UNC result sets remain an explicit empty `object[]`, so report generation does not receive `$null` after a completely failed import.
- Beta 6 conditional folder-language prompt and Error-folder cleanup remain unchanged.

## 0.11.54 beta 6 test focus

- Queue folder language prompt now appears only when a matching external subtitle lacks an explicit language suffix; one choice applies to all such subtitles in that folder.
- Folders with no matching subtitles, or only explicitly tagged subtitles such as `.en/.eng/.sv/.swe`, are added without a language dialog.
- Removing the final error item belonging to a queue folder now removes that empty folder from the active queue/settings as well.

This beta adds per-folder subtitle-language control for UNC queue items and hardens failed-media handling. When a queue folder is added, MediaPrep asks which installed language should be used for untagged subtitles and offers a default-on filename override. Files such as `Series 1x02.en.srt`, `Series 1x02.eng.srt`, `Series 1x02.sv.srt`, and `Series 1x02.swe.srt` match `Series 1x02.<video>` while the explicit language suffix can control MKV metadata. Failed UNC imports remain errors, do not enter the return stage, do not cause unrelated Processed MKVs to be analyzed, keep the remote source intact, and allow later queue folders to continue. Beta 4 TV/Film/Other classification and episode-number sequence detection remain unchanged.

## Overview

MediaPrep MKV Toolkit is a Windows PowerShell 5.1 workflow for processing video files into MKV. It can mux compatible source files without unnecessary video re-encoding, handle external subtitles, analyze media with FFprobe, optionally reduce file size using a verified HEVC encoder, process local or UNC/network queues, and keep runtime statistics.

The project intentionally remains PowerShell-based. There is no compiled application executable, which keeps the source readable and makes the workflow easier to inspect, maintain, and extend.

## Features

- Windows PowerShell 5.1 based Start Center and processing workflow
- TS, MP4, AVI, MPG, MPEG, and optional MKV source support
- MKV output
- Subtitle handling for SRT and VTT
- VTT-to-SRT conversion when required
- Subtitle muxing without burn-in
- FFprobe analysis before and after processing
- Optional HEVC encoding
- CPU encoding with `libx265`
- NVIDIA HEVC NVENC support
- Intel HEVC QSV support
- AMD/Radeon HEVC AMF support when compatible hardware is present
- Hardware detection and real encoder verification
- Short 1080p encoder benchmark with speed and SSIM results
- NVIDIA capability testing and VRAM/utilization information when available
- Local processing and UNC/network queue processing
- One UNC queue root processed completely before the next queue begins
- Restart-safe queue handling
- Error queue with review, continue, and remove actions
- Live queue dashboard and runtime statistics
- Copy-in and copy-back statistics
- Slow-copy diagnostics
- Queue save/load support
- Archived session statistics
- FFmpeg and MKVToolNix management
- Online selection of recent FFmpeg and MKVToolNix versions
- Local tool backup and rollback
- Light, Dark, Monthly, and Custom interface themes
- 14 interface languages with dynamic locale discovery

## Requirements

MediaPrep MKV Toolkit is intended for Windows and uses:

- Windows PowerShell 5.1
- FFmpeg / FFprobe
- MKVToolNix / `mkvmerge`
- Optional compatible NVIDIA, Intel, or AMD GPU for hardware HEVC encoding

FFmpeg and MKVToolNix binaries are **not included in the repository**.

They can be verified, downloaded, updated, or changed from MediaPrep under:

**Settings → Check / download external tools**

MediaPrep stores the active external tools under:

```text
Tools\FFmpeg\ffmpeg.exe
Tools\FFmpeg\ffprobe.exe
Tools\MKVToolNix\mkvmerge.exe
```

Before replacing an active FFmpeg or MKVToolNix installation, MediaPrep keeps a local backup under `Tools\ToolBackups`.

## Supported source formats

MediaPrep currently handles:

```text
.ts
.mp4
.avi
.mpg
.mpeg
```

Output is written as MKV.

On the **Options** tab, each source format can be enabled or disabled independently:

```text
TS    MP4    AVI    MPG    MPEG    MKV
```

TS, MP4, AVI, MPG, and MPEG are enabled by default. MKV is disabled by default. This makes it possible to run a queue only for selected legacy formats, for example AVI and MP4.

When MKV is enabled, existing MKV files skip the remux stage and go directly to FFprobe analysis and optional HEVC re-encoding. The original source is not replaced until the prepared/encoded output has passed MediaPrep verification.

For an UNC MKV source, the normal **delete original after success** setting means the verified result safely replaces the original MKV path. If original deletion is disabled, MediaPrep preserves the original and publishes the result as `name.mediaprep.mkv`.

MediaPrep uses FFprobe to inspect the source before processing so container, codec, resolution, frame rate, pixel format, duration, bitrate, and stream information can be evaluated before muxing or encoding.

## Subtitles

External subtitles can be matched with the source video.

Supported subtitle formats:

```text
.srt
.vtt
```

SRT is preferred when both formats are present.

In UNC Queue mode, each folder has its own subtitle-language option. The dropdown is populated from installed MediaPrep language resources. Untagged subtitles such as `Movie.srt` or `Movie.vtt` use the language selected for that folder. With the filename-language override enabled (the default), explicit recognized suffixes take precedence, for example:

```text
Series 1x02.en.srt   -> English
Series 1x02.eng.srt  -> English
Series 1x02.sv.srt   -> Swedish
Series 1x02.swe.srt  -> Swedish
```

The language suffix is ignored when matching the subtitle to the video basename, so all four examples above match `Series 1x02.ts`, `Series 1x02.mkv`, or another selected video format with the same basename. As more valid locale JSON files are installed, their standard two- and three-letter language codes become available to the same mechanism.

VTT subtitles can be converted to temporary SRT files before muxing. Subtitles are muxed into the MKV as selectable subtitle tracks; they are not burned into the video.

MediaPrep can also create an MKV when no matching subtitle exists. Existing MKV results may be rerun when a new matching external subtitle is added, provided MKV input is selected for that run.

## CPU/GPU encoder verification

MediaPrep detects available CPU and GPU encoder candidates and verifies them with real short HEVC test encodes before they are considered usable.

Supported backend candidates are:

| Hardware | Backend | FFmpeg encoder |
|---|---|---|
| CPU | CPU | `libx265` |
| NVIDIA GPU | NVENC | `hevc_nvenc` |
| Intel GPU / compatible Intel Arc or iGPU | QSV | `hevc_qsv` |
| AMD / Radeon GPU | AMF | `hevc_amf` |

Hardware that is not present in the computer is not offered as an active encoder.

The encoder test uses a reproducible 1920×1080, 30 fps test source and records benchmark information such as:

- Encoding speed
- SSIM
- Output size
- Verification result

For NVIDIA hardware, MediaPrep can also record VRAM usage, GPU utilization, encoder utilization, and temperature when `nvidia-smi` is available.

NVIDIA capability checks include:

- CUDA decode
- Preset P4
- VBR / CQ
- Spatial AQ
- Temporal AQ
- Lookahead 16
- Surfaces 8
- Multipass qres

Capability and benchmark results are stored under `Data`. The latest checked CPU/GPU hardware summary is also stored in `Data\mediaprep.preferences.json` and is reused during normal Start Center startup when it belongs to the current computer. This avoids repeated Windows CIM/WMI hardware discovery for information that rarely changes. **Refresh hardware** or **Check CPU/GPU** updates the saved hardware snapshot. Queue start still performs a fresh CPU/GPU/driver and FFmpeg signature validation before processing begins, so cached display information does not bypass encoder safety checks.

## Queue processing

MediaPrep supports both local processing and UNC/network queues.

In Queue mode, each UNC queue root is completed before the next queue starts:

```text
Import
  ↓
Mux
  ↓
Analyze
  ↓
Optional HEVC encode
  ↓
Return to UNC
  ↓
Local cleanup
  ↓
Next queue
```

This design prevents MediaPrep from importing many independent network queues at once and unnecessarily filling the local work disk.

Restart-safe queue logic can reuse complete local source files and avoid unnecessary re-copying when a valid processed MKV already exists.

## Error handling

Files that cannot be processed safely can be moved into the MediaPrep error queue while the remaining queue continues.

The error queue supports:

- **Review** — open the local MKV for inspection
- **Continue** — return the item to the best safe processing stage
- **Remove** — remove the item from the MediaPrep queue and clean only local working/temp files

Removing an item from the MediaPrep error queue does not delete the original UNC source.

An optional **Ignore decode errors** setting is available for files that need tolerant FFmpeg decoding.

## Queue dashboard and statistics

The Queue Dashboard can display live processing information and session statistics.

MediaPrep tracks information such as:

- Remaining files
- Processed / total files
- Remaining size
- Files ready to return
- Copy-in and copy-back activity
- Average transfer speed
- Slow-copy events
- Current processing stage
- Error queue items

Session statistics can be archived under:

```text
Data\Statistics\
```

Saved historical sessions can be loaded in the dashboard without altering the current queue.

MediaPrep can also save and reopen queue packages containing the queue list and relevant runtime state.

## External tool management

MediaPrep can manage FFmpeg and MKVToolNix from the Settings tab.

The tool manager supports:

- Checking installed versions
- Downloading/updating tools
- Selecting from recent available online versions
- Testing a staged FFmpeg build before activation
- Keeping local backups of replaced versions
- Restoring a previous local version

Changing FFmpeg invalidates the previous encoder verification so an incompatible capability result cannot silently be reused.

The Start Center banner displays the active FFmpeg and MKVToolNix versions.

### MediaPrep version management

The same version manager can check GitHub Releases for up to the five most recent published MediaPrep versions. A newer release can be installed, or an older published release can be selected deliberately.

Before MediaPrep program files are replaced, the current program version is backed up under:

```text
Data\ProgramBackups\
```

MediaPrep updates replace program files only. Existing `Data`, queue state, statistics, preferences, downloaded tools, logs, and media working folders are preserved. The update is applied by a separate updater process after Start Center closes, then MediaPrep is restarted. If activation fails, the updater attempts to restore the previous program files automatically.

## Process diagnostics

The Start Center can display MediaPrep-started process names and process IDs (PIDs). This makes it easier to identify a remaining PowerShell, FFmpeg, MKVToolNix, queue-host, or related child process if a processing session is interrupted or the interface is closed unexpectedly.

Basic startup diagnostics and early-failure tracing are written to `Loggar\MediaPrep-Startup.log`. When **Verbose logging** is enabled and MediaPrep is restarted, a separate timestamped `Loggar\MediaPrep-Startup_YYYY-MM-DD_HH-mm-ss.log` is retained with the full fine-grained timing trace. The verbose startup log records real timestamps, elapsed milliseconds, and `Start`/`End` duration markers for initialization stages such as encoder refresh, external-tool version checks, process discovery, path checks, theming, and settings synchronization. Detailed timing markers are intentionally kept out of the basic startup log, making the timestamped verbose logs suitable for comparison across machines and across older/newer starts.

Verbose startup timing also records whether the CPU/GPU snapshot came from saved preferences, current-session memory, or a fresh Windows CIM read. This makes performance logs useful for comparing normal cached starts with deliberate hardware refreshes.

## Themes and language

Available interface themes include:

- Light
- Dark
- Monthly
- Custom

The Monthly theme selects an automatic palette based on the current month. Custom mode stores separate banner, panel/accent, and background colors.

Language files are stored under:

```text
Languages\
    mediaprep.en-US.json   English
    mediaprep.sv-SE.json   Svenska
    mediaprep.de-DE.json   Deutsch
    mediaprep.fr-FR.json   Français
    mediaprep.es-ES.json   Español
    mediaprep.it-IT.json   Italiano
    mediaprep.fi-FI.json   Suomi
    mediaprep.nb-NO.json   Norsk bokmål
    mediaprep.da-DK.json   Dansk
    mediaprep.is-IS.json   Íslenska
    mediaprep.nl-NL.json   Nederlands
    mediaprep.zh-CN.json   简体中文
    mediaprep.hi-IN.json   हिन्दी
    mediaprep.bn-BD.json   বাংলা
```

Language resources use BCP-47 culture names and JSON. The current distribution includes all 14 resources above. **System default** resolves the Windows UI culture to an installed resource; if the exact regional culture is not installed, MediaPrep first tries an installed resource for the same language and finally falls back to `en-US`.

Each language file declares `SchemaVersion`, `LanguageFileVersion`, `Culture`, and its native display name. `en-US` is the authoritative master/fallback and is frozen for 0.11.54. In 0.11.54 all 14 resources use schema 1 / language-file version 1.7.5 and contain the same 739 keys in the same order with the same format placeholders. Additional valid `mediaprep.<culture>.json` files can still be discovered automatically by the language selector.

Before a language package is accepted for release, `App\Test-MediaPrepLanguages.ps1` can validate UTF-8 BOM, JSON parsing, schema/version/culture metadata, exact key count and ordering, placeholder compatibility, empty strings, common mojibake patterns, and literal language-key references in the shipped PowerShell sources. Normal user-facing text is kept in the shared JSON resources; low-level troubleshooting diagnostics may intentionally remain English.

## Installation

### Option 1 - PowerShell web installer

The easiest way to install the latest published MediaPrep release is with the PowerShell web installer.

Open **Windows PowerShell** and run:

```powershell
$installer = "$env:TEMP\Install-MediaPrep-Web.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/main/Installer/Install-MediaPrep-Web.ps1" -OutFile $installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
```

The default installation folder is:

```text
C:\MediaPrep MKV Toolkit
```

A different location can be supplied explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -InstallPath "D:\MediaPrep MKV Toolkit"
```

The web installer checks the latest GitHub Release, downloads the packaged ZIP, verifies SHA-256 when GitHub provides a digest, extracts the package, and installs it directly. It also repairs UTF-8 BOM issues in the CMD launchers from older packages.

If the computer enforces PowerShell **ConstrainedLanguage**, installation can still complete, but MediaPrep's graphical Start Center requires **FullLanguage**. The installer and Start Center provide a clear warning instead of allowing the user to continue unnecessary FFmpeg/GPU troubleshooting.

### Option 2 - Packaged GitHub release

Download the packaged ZIP from the [Releases](https://github.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases) page.

Extract the ZIP and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\Install-MediaPrep.ps1
```

The installer lets you select an installation folder and creates the MediaPrep directory structure.

External FFmpeg and MKVToolNix binaries are not bundled with the installer.

### Option 3 - Portable use

Extract the packaged release to a folder and start:

```text
Start MediaPrep.cmd
```

Then configure or download the external tools from MediaPrep Settings.

## Directory layout

A normal installation uses the following structure:

```text
MediaPrep MKV Toolkit\
├─ Start MediaPrep.cmd
├─ README.md
├─ CHANGELOG.md
├─ LICENSE
├─ LICENSE.md
├─ THIRD-PARTY-LICENSES.md
├─ ENCODER-LICENSING.md
├─ THIRD-PARTY-NOTICES.md
├─ App\
│  ├─ MediaPrep-Start.ps1
│  ├─ MediaPrep.ps1
│  ├─ MediaPrep-Queue.ps1
│  ├─ MediaPrep-Queue-Host.ps1
│  ├─ MediaPrep-Queue-Dashboard.ps1
│  ├─ MediaPrep-Encoder-Test.ps1
│  ├─ MediaPrep-Updater.ps1
│  ├─ Manage-MediaPrepTools.ps1
│  └─ Install-MediaPrep.ps1
├─ Data\
│  ├─ Temp\
│  ├─ Downloads\
│  ├─ Statistics\
│  └─ ProgramBackups\
├─ Error\
├─ Installer\
│  └─ Install-MediaPrep-Web.ps1
├─ Languages\
├─ Loggar\
├─ Processed\
├─ Rapporter\
├─ Tools\
│  ├─ FFmpeg\
│  ├─ MKVToolNix\
│  └─ ToolBackups\
└─ UnProcessed\
```

Git does not track empty directories, so `.gitkeep` files are used where required in the repository.

Runtime-generated data, logs, downloaded tools, media files, statistics, and local preferences are excluded from Git by `.gitignore`.

## Default working folders

- `UnProcessed` — local source files waiting to be processed
- `Processed` — completed MKV files
- `Error` — local files requiring manual review
- `Data` — settings, indexes, manifests, queue state, and runtime data
- `Data\Temp` — temporary working files
- `Data\Downloads` — tool download/staging area
- `Data\Statistics` — archived session statistics
- `Loggar` — application and processing logs
- `Rapporter` — generated reports
- `Languages` — interface language files
- `Tools\FFmpeg` — active FFmpeg/FFprobe installation
- `Tools\MKVToolNix` — active MKVToolNix installation
- `Tools\ToolBackups` — locally backed-up external tool versions

Existing installations that explicitly use the older `Filmer` folder remain supported. New installations use `UnProcessed`.

## Starting MediaPrep

Use:

```text
Start MediaPrep.cmd
```

as the normal entry point.

MediaPrep normally starts without elevation. Administrator rights are requested only when needed, such as when the saved option to prevent automatic Windows Update restart during a queue requires elevation.

## Updating

For future versions:

1. Download the new packaged release or update package.
2. Stop any running MediaPrep queue.
3. Apply the update according to the release notes.
4. Start MediaPrep again.
5. Re-run CPU/GPU verification if MediaPrep reports that the previous encoder capability profile is no longer valid.

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Repository contents

The GitHub repository contains the MediaPrep source, documentation, language files, and required empty-directory placeholders.

It intentionally does **not** contain:

- User media
- Runtime logs
- Runtime statistics
- Local configuration/preferences
- FFmpeg binaries
- MKVToolNix binaries
- Tool backups
- Temporary processing files

## License

Copyright © 2026 Anders Syrén.

MediaPrep MKV Toolkit is licensed under **GNU GPL version 3 or any later version (`GPL-3.0-or-later`)**.

- [`LICENSE`](LICENSE) contains the complete GPLv3 license text.
- [`LICENSE.md`](LICENSE.md) explains the MediaPrep project notice and the “or later” choice.
- Source scripts carry an SPDX `GPL-3.0-or-later` identifier.

The GPL applies to the MediaPrep code. It does **not** change the licenses of FFmpeg, MKVToolNix, GPU drivers/SDKs or codec implementations.

## Third-party software and encoders

MediaPrep deliberately keeps third-party licensing separate from the MediaPrep source-code license. Official MediaPrep ZIPs do not bundle FFmpeg, ffprobe or MKVToolNix binaries.

- [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md) documents the external-tool boundary and current download sources.
- [`ENCODER-LICENSING.md`](ENCODER-LICENSING.md) distinguishes encoder software/API licensing from codec/patent licensing and records AV1 as the preferred future lower-licensing-friction candidate.
- [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) is the short notice/index.

The licensing documents are intended to make the technical boundaries clear; they are not legal advice.

## Changelog

Detailed release history is available in [CHANGELOG.md](CHANGELOG.md).

## Author

Created by **Anders Syrén**.

### 0.11.53 startup and dashboard behavior

- Start Center shows the MediaPrep splash screen during startup and keeps it visible for about one second after the main window appears.
- Verbose logging writes detailed startup timing for troubleshooting slow startup.
- CPU/GPU summary data can be reused from verified preferences to avoid unnecessary repeated hardware discovery.
- When the user explicitly closes Start Center, Start Center closes the queue statistics window as UI cleanup; the independent queue process is not terminated. If Start Center crashes or is terminated unexpectedly, the queue statistics window remains available so a running queue can still be monitored.
- A deliberate MediaPrep update also closes Dashboard windows for the same installation before activation.

### Encoder preference persistence

CPU/libx265 is used only as the first-run default when no encoder preference exists. Once a verified encoder is selected by the user, `SelectedEncoderId` is preserved across normal restarts and MediaPrep updates. Release ZIP packages do not overwrite an existing `Data\mediaprep.preferences.json` or `Data\config.json`; Start Center creates these files automatically on first launch when they are missing.

### 0.11.53 localization

Runtime console output, Queue Dashboard text, recovery dialogs, and saved-queue dialogs use the same locale-based language resources as Start Center. The selector has three modes but only two built-in translation resources: **System default** resolves Windows UI culture, **English** forces `en-US`, and **Svenska** forces `sv-SE`.

Language resources are locale-named JSON files with schema/version metadata:

```text
Languages\mediaprep.en-US.json
Languages\mediaprep.sv-SE.json
```

Additional valid cultures can be discovered automatically. `en-US` is the safe master fallback for missing or malformed translated strings.

### 0.11.53 update safety

MediaPrep checks for an active queue/media worker immediately before launching the updater. The updater repeats the check after Start Center exits and before changing any program files. If work is active, the update is cancelled without stopping the queue or closing its Dashboard.


## 0.11.54 beta 1 development note

This beta adds explicit TV / Film / Other classification and a selectable target profile for unrecognized files. Duration is used for MB/min calculations, never to decide whether a title is a TV episode or a film. Per-file classification and ratio data is preserved in Dashboard statistics for later tuning.
