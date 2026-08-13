# MediaPrep MKV Toolkit

PowerShell toolkit for preparing, muxing, analyzing, organizing, and optionally re-encoding video files to MKV.

**Current release: 0.11.53**

[Download the latest packaged release](https://github.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases/latest)

> **License:** Source available for personal, non-commercial use. MediaPrep MKV Toolkit is not distributed under an OSI-approved open-source license. See [LICENSE.md](LICENSE.md).

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
- Swedish and English interface language files

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

VTT subtitles can be converted to temporary SRT files before muxing. Subtitles are muxed into the MKV as selectable subtitle tracks; they are not burned into the video.

MediaPrep can also create an MKV when no matching subtitle exists.

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
    mediaprep.en-US.json
    mediaprep.sv-SE.json
```

Language resources use BCP-47 culture names and JSON. The current distribution includes English (`en-US`) and Swedish (`sv-SE`). **System default** resolves the Windows UI culture to an installed resource; if the exact regional culture is not installed, MediaPrep first tries an installed resource for the same language and finally falls back to `en-US`.

Each language file declares `SchemaVersion`, `LanguageFileVersion`, `Culture`, and its native display name. MediaPrep validates the schema before loading the resource. `en-US` is the authoritative fallback for missing keys or broken format placeholders, so an older same-schema translation cannot crash the application simply because a newer text key is absent. Additional valid `mediaprep.<culture>.json` files can be discovered automatically by the language selector.

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
├─ LICENSE.md
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

Copyright © 2026 Anders Syrén. All rights reserved.

MediaPrep MKV Toolkit is **source available for personal, non-commercial use**.

Commercial use, commercial redistribution, paid inclusion, and other uses restricted by the license require prior written permission from Anders Syrén.

See [LICENSE.md](LICENSE.md) for the complete license terms.

This license is **not an OSI-approved open-source license**.

## Third-party software

MediaPrep can use third-party tools including FFmpeg and MKVToolNix. These projects are distributed under their own licenses and are not included under the MediaPrep MKV Toolkit license.

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

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
