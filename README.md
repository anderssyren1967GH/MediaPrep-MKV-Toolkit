# MediaPrep MKV Toolkit

PowerShell toolkit for preparing, muxing, analyzing, organizing, and optionally re-encoding video files to MKV.

**Current release: 0.11.51**

[Download the latest packaged release](https://github.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases/latest)

> **License:** Source available for personal, non-commercial use. MediaPrep MKV Toolkit is not distributed under an OSI-approved open-source license. See [LICENSE.md](LICENSE.md).

## Overview

MediaPrep MKV Toolkit is a Windows PowerShell 5.1 workflow for processing video files into MKV. It can mux compatible source files without unnecessary video re-encoding, handle external subtitles, analyze media with FFprobe, optionally reduce file size using a verified HEVC encoder, process local or UNC/network queues, and keep runtime statistics.

The project intentionally remains PowerShell-based. There is no compiled application executable, which keeps the source readable and makes the workflow easier to inspect, maintain, and extend.

## Features

- Windows PowerShell 5.1 based Start Center and processing workflow
- TS, MP4, AVI, MPG, and MPEG source support
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

Capability and benchmark results are stored under `Data`. A new CPU/GPU verification is required when the relevant FFmpeg build, GPU, or graphics driver changes.

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

## Process diagnostics

The Start Center can display MediaPrep-started process names and process IDs (PIDs). This makes it easier to identify a remaining PowerShell, FFmpeg, MKVToolNix, queue-host, or related child process if a processing session is interrupted or the interface is closed unexpectedly.

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
```

The current distribution includes Swedish and English language files.

## Installation

### Option 1 — packaged GitHub release

Download the packaged ZIP from the [Releases](https://github.com/anderssyren1967GH/MediaPrep-MKV-Toolkit/releases) page.

Extract the ZIP and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\App\Install-MediaPrep.ps1
```

The installer lets you select an installation folder and creates the MediaPrep directory structure.

External FFmpeg and MKVToolNix binaries are not bundled with the installer.

### Option 2 — portable use

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
│  ├─ Manage-MediaPrepTools.ps1
│  └─ Install-MediaPrep.ps1
├─ Data\
│  ├─ Temp\
│  ├─ Downloads\
│  └─ Statistics\
├─ Error\
├─ Installer\
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
