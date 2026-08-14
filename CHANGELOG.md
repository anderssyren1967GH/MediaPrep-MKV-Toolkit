# Changelog

## 0.11.54 - 2026-08-14

- Final release built directly from the validated 0.11.54 beta 12 checkpoint.
- No functional mux, queue, encoder, classification, subtitle-language, Dashboard, or CPU/GPU layout changes were introduced for final packaging.
- Ships 14 synchronized interface languages (schema 1, LanguageFileVersion 1.7.5, 739 keys) and the corrected language validator.
- Includes GPL-3.0-or-later licensing for MediaPrep source code with separate third-party and encoder/codec licensing documentation.
- Preserves restart-safe UNC processing, error-queue cleanup, All-in-one statistics, TV/Film/Other classification including episode-number sequences, and per-folder subtitle-language handling.
- Post-publication release test: verify a real GitHub update from 0.11.53 to 0.11.54, including updater backup/install/automatic restart and preserved settings.

## 0.11.54 beta 12 - 2026-08-14

- Fixed a false-positive mojibake validation error for legitimate lowercase accented characters by changing the validator mojibake regex from case-insensitive `-match` to case-sensitive `-cmatch`.
- Confirmed the French `QueueConsoleJobMissing` text is valid UTF-8 and does not require a translation change.
- Language resources remain schema 1 / LanguageFileVersion 1.7.5 with 739 keys across all 14 languages; no locale JSON files were modified.
- Processing, queue, Dashboard, encoding, classification, subtitle-language and CPU/GPU layout logic are unchanged from beta 11.

## 0.11.54 beta 11 - 2026-08-14

- Polished Dashboard localization after beta 10 multilingual testing.
- Reapplies localized Dashboard tabs, captions, grid headers and buttons after form construction and when the saved language preference changes.
- Localizes slow-copy direction values (`In` / `Out`).
- LanguageFileVersion is now `1.7.5`; all 14 language files contain 739 keys in identical order with identical placeholders.
- Muxing, queue processing, encoding, classification and CPU/GPU layout are unchanged.

## 0.11.54 beta 10 - 2026-08-14

- Froze `Languages\mediaprep.en-US.json` as the authoritative 0.11.54 localization master: schema 1, LanguageFileVersion 1.7.4, 737 keys.
- Added twelve complete locale resources: German, French, Spanish, Italian, Finnish, Norwegian Bokmål, Danish, Icelandic, Dutch, Simplified Chinese, Hindi, and Bengali. Together with English and Swedish, MediaPrep now ships 14 interface languages.
- All 14 locale files use UTF-8 with BOM, the same 737 keys in exactly the same order, and the same format placeholders as the en-US master.
- Added `Languages\README.md` and `Languages\MASTER-en-US-0.11.54.sha256` to document the frozen master and translation maintenance rules.
- Dynamic language discovery remains unchanged: the Start Center, system-default resolver, and per-folder subtitle-language selector discover valid `mediaprep.<culture>.json` resources automatically.
- No language-resource keys were added and LanguageFileVersion remains 1.7.4. Muxing, queue/UNC processing, subtitle handling, classification, ratios, encoding, Dashboard behavior, and CPU/GPU layout are intentionally unchanged from beta 9.

## 0.11.54 beta 9 - 2026-08-14

- Relicensed the MediaPrep source code under GNU GPL version 3 or any later version (`GPL-3.0-or-later`), replacing the previous personal/non-commercial source-available license.
- Added the complete GPLv3 license text as `LICENSE`, replaced `LICENSE.md` with a concise project notice, and added SPDX GPL identifiers to shipped PowerShell/CMD source files.
- Added `THIRD-PARTY-LICENSES.md` and `ENCODER-LICENSING.md` to clearly separate MediaPrep copyright licensing, external-tool licensing, hardware API/SDK licensing and codec/patent considerations.
- Documented the current external-tool model: official MediaPrep ZIPs do not bundle FFmpeg/ffprobe/MKVToolNix; the FFmpeg helper currently selects Gyan release-essentials builds, which Gyan identifies as GPLv3 builds.
- Documented AV1/libaom and other AV1 paths as future lower-licensing-friction candidates without changing MediaPrep's existing HEVC encoding behavior.
- Fixed `Test-MediaPrepLanguages.ps1` on Windows PowerShell 5.1 by resolving `$PSScriptRoot`/script path after `param(...)` binding and excluding the validator itself from the legacy `Msg(...)` source scan.
- No language-resource keys or processing behavior were intentionally changed; en-US/sv-SE remain at LanguageFileVersion 1.7.4 with 737 keys.

## 0.11.54 beta 8 - 2026-08-13

- Completed the pre-translation localization audit without intentionally changing muxing, queue, classification, encoding, subtitle, statistics, or CPU/GPU behavior.
- Migrated remaining normal user-facing strings to the shared locale JSON resources in the processing engine, Start Center, Queue Dashboard, queue console, external-tool/version manager, encoder verification, updater, local installer, GitHub web installer, and early startup paths.
- Replaced the legacy bilingual `Msg(...)` implementation in `Manage-MediaPrepTools.ps1` with the common JSON language loader and en-US fallback.
- Added common localization loading to Queue console, encoder-test live status, updater errors, local installer and web installer. The web installer now delays its normal banner until the release language resource is available.
- Localized remaining operator-visible runtime exceptions, mux/cleanup/recommendation reasons, queue messages, updater failures, startup failures, and the last visible Dashboard fallback. Low-level troubleshooting diagnostics remain English by design.
- Reorganized the flat language JSON files into identical logical blocks with alphabetic keys inside each block.
- Added `App\Test-MediaPrepLanguages.ps1` to validate UTF-8 BOM, JSON/schema/language version, Culture/filename metadata, exact key count/order, placeholders, empty translations, mojibake, source key references and legacy `Msg(...)` usage.
- Language resources increased to schema 1 / LanguageFileVersion 1.7.4 with 737 identical keys in `en-US` and `sv-SE`. `en-US` remains the master/fallback.
- The additional planned translations are intentionally not included yet; the English master is to be frozen only after beta 8 localization/regression testing.

## 0.11.54 beta 7 - 2026-08-13

- Fixed UNC import/mux regression introduced with subtitle-language matching in beta 5 and exposed by valid-media testing in beta 6.
- Avoids the Windows PowerShell `Argument types do not match` failure caused by `@(...)` around `New-Object System.Collections.Generic.List[object]`.
- Subtitle language discovery/matching now uses safe `.Count` and `.ToArray()` access.
- Fixed zero-result UNC analysis so an empty result stays an empty `object[]` instead of collapsing to `$null` before report generation.
- Preserves beta 6 conditional subtitle-language prompt and queue-folder cleanup behavior.
- Language resources remain schema 1 / LanguageFileVersion 1.7.3; no new localization keys.

## 0.11.54 beta 6 - 2026-08-13

- Refined per-folder subtitle language prompting: no dialog is shown when a folder has no matching external subtitles or when every matching subtitle already carries a recognized language suffix such as `.en/.eng/.sv/.swe`.
- When one or more matching subtitles are untagged, MediaPrep asks once for the folder language and applies that choice to all untagged subtitles in that queue folder. Explicit filename language codes continue to override when enabled.
- Removing the last error item from a queue folder now also removes that now-empty folder from `UncQueue`, its per-folder options, the current job state, and current-session queue statistics.
- Language resource version increased to 1.7.3.

## 0.11.54 beta 5 - 2026-08-13

- Added per-UNC-folder subtitle language options when a folder is added to Queue mode. The language dropdown is built dynamically from the installed `Languages\mediaprep.*.json` resources; English is the default for new folders in this beta.
- Added a default-on filename-language override. Explicit subtitle suffixes such as `.en.srt`, `.eng.srt`, `.sv.srt`, and `.swe.srt` are matched to the corresponding video and, when override is enabled, control the MKV subtitle language/track name.
- Untagged subtitles such as `Movie.vtt` use the language selected for that queue folder. Folder subtitle options are saved with queue settings/packages so they survive restart/save/load, while the options dialog is shown again whenever a folder is added.
- Removed the hardcoded `swe` / `Svenska` subtitle metadata path. Subtitle language metadata is now derived from the selected folder culture or an explicit recognized filename suffix.
- Existing processed MKV results can be rerun when a new matching external subtitle is present (or Force remux is selected), allowing a folder to be processed again to add/fix subtitle tracks.
- Fixed failed UNC imports being overwritten from `Error` to `WaitingForReturn`. Only successful import records may enter the return stage.
- Fixed an explicit empty UNC analysis set being interpreted as “analyze the whole Processed folder”; a failed import with zero current outputs now analyzes zero MKVs instead of reusing unrelated old cache entries, and the existing analysis cache is preserved rather than replaced by an empty set.
- A failed UNC import/probe now makes that queue item return a non-zero result while the queue continues with later folders. The failed folder remains in the queue for rerun, the UNC original is kept, and invalid local staging files are removed.
- `Ignore decode errors` does not convert an unreadable source/import failure into success; it remains an encoding-tolerance option.
- Language resource version increased to 1.7.2. TV/Film/Other classification, numbered episode-sequence detection, ratio calculations, CPU/GPU layout, and the proven encoding/UNC isolation model are otherwise unchanged.

## 0.11.54 beta 4 - 2026-08-13

- Added safe TV-series detection for numbered episode sequences such as `Descendants of the Sun 04/05` and `Naruto (Dub) 009/010`.
- Sequence detection requires at least two files in the same folder with the same normalized title prefix and different trailing 2-3 digit numbers; a lone numeric title is not classified as TV by this rule.
- File details/statistics now show `Episode number sequence` / `Avsnittsnummersekvens` as the detection reason.
- Analysis cache model was advanced so older beta analysis entries are recalculated once and do not keep stale `Other` classifications.
- Language resource version increased to 1.7.1 for the new detection reason.
- Existing explicit episode patterns, year-based film detection, queue/UNC processing, MKV subtitle remuxing and All in one Dashboard inventory behavior are otherwise unchanged.

## 0.11.54 beta 3 - 2026-08-13

- Fixed All in one Dashboard inventory: selected local files are registered before the queue starts instead of leaving the Dashboard at 0/0.
- The File details tab now receives classification, detection reason, target profile and MB/min values during All in one runs just as it already did in normal queue mode.
- Successful All in one files are marked Completed after analysis/optional encoding because there is no UNC return stage in this mode.
- Normal queue/UNC processing and the beta 2 MKV + external subtitle remux fix are otherwise unchanged.

## 0.11.54 beta 2 - 2026-08-13

- Fixed MKV input with matching external `.srt`/`.vtt`: MKV sources now discover external subtitles and are remuxed with them instead of always bypassing the mux path.
- `Force remux` now also applies to selected MKV input. MKV without an external subtitle still uses the fast direct preparation path when force remux is off.
- Added safe same-path MKV remux handling so a source is never deleted before a verified replacement exists.
- Fixed unfinished-session recovery appearing behind the TopMost splash. The splash is closed before the recovery prompt and the prompt is explicitly brought to the foreground.
- Startup diagnostics now identify the build as `0.11.54 beta 2`.

## 0.11.54 beta 1 - 2026-08-13

- Media classification no longer uses duration as a fallback. Episode patterns classify TV, year patterns classify films, and unrecognized names remain `Other`.
- Added a saved `Target profile for Other files` preference (`TV series` or `Film`) so unknown names use the selected MB/min model without being misclassified.
- Analysis now stores classification, detection reason, target profile, duration in minutes, actual MB/min, target MB/min, estimated target size and estimated saving.
- Queue Dashboard adds a `File details` tab that shows classification and ratio data during a run and in archived statistics.
- Queue dashboard inventory schema increased to version 4 and session statistics preserve the new per-file analysis fields.
- Removed the old duration-based TV/film fallback.
- Hardened post-update restart: the updater starts `MediaPrep-Start.ps1` directly, logs the restart PID and falls back to the CMD launcher if the direct restart exits early.
- `Start MediaPrep.cmd` now launches the Start Center as a detached hidden-console PowerShell process, improving restart reliability when an older updater launches the newly installed package.
- Language resource version increased to 1.7.0 for the new TV/Film/Other and ratio/detail labels. Only English and Swedish are shipped while localization cleanup is still in progress.
- Three remaining internal Swedish verbose/debug messages were changed to English.

## 0.11.53 - 2026-08-13

- Added an independent startup splash screen and permanent startup diagnostics. The basic startup log remains compact, while Verbose logging adds timestamped fine-grained startup stage timings for troubleshooting.
- Reduced Start Center startup time by reusing verified CPU/GPU information from preferences and an in-memory encoder signature snapshot instead of repeatedly querying FFmpeg and Windows hardware during one startup session.
- Queue start remains a safety boundary: a fresh encoder/FFmpeg/hardware validation is still performed before processing begins.
- Preserves the user's last explicitly selected encoder across restarts and updates. CPU/libx265 is now only the first-run default when no saved encoder preference exists.
- Full release packages no longer include live `Data\config.json` or `Data\mediaprep.preferences.json`, preventing manual full-ZIP overlays from overwriting existing user settings. Missing files are created automatically on first launch.
- Added locale-based JSON language resources under `Languages\`, currently `mediaprep.en-US.json` and `mediaprep.sv-SE.json`, with dynamic discovery for future languages.
- Added language-resource validation with `SchemaVersion = 1` and `LanguageFileVersion = 1.6.0`. `en-US` is the authoritative fallback for missing keys, incompatible resources, or invalid format placeholders.
- Runtime console output, Queue Dashboard, unfinished-session recovery, and saved-queue dialogs now follow the selected language. The UI keeps three language modes: System default, English, and Svenska.
- Fixed Queue Dashboard localization/statistics rendering, including loading older archived statistics that do not contain a root session status.
- Queue Dashboard is closed only by deliberate Start Center UI cleanup or a deliberate MediaPrep update. An unexpected Start Center termination leaves Dashboard available so an independent running queue can still be monitored.
- Added a two-stage update safety gate. Start Center blocks MediaPrep/external-tool version changes while a MediaPrep queue or media worker is active, and the separate updater repeats the worker check before changing program files.
- Deliberate MediaPrep updates close Dashboard windows for the same installation before activation, while queue/media processes themselves are never terminated by dashboard cleanup.
- Installer/updater paths make a best-effort attempt to remove Windows Internet-zone markers from verified/copied MediaPrep program files to reduce unnecessary publisher warnings after downloaded installs and updates.
- Continued controlled source-language cleanup: internal diagnostics/comments in the queue and encoder-host paths are English while user-visible runtime text is localized through language resources.
- The proven CPU/GPU layout and the existing muxing, encoding, UNC isolation, queue data format, statistics calculations, error queue, and rollback model are otherwise unchanged.

## 0.11.52 - 2026-08-12

- Added MediaPrep self-update/version management through GitHub Releases. Up to five recent published MediaPrep versions can be listed and selected, including deliberate downgrade to an older published version.
- MediaPrep program files are backed up under `Data\ProgramBackups` before update/restore. A separate updater process applies program files after Start Center closes, preserves user/runtime data, restarts MediaPrep, and attempts automatic rollback on activation failure.
- Existing FFmpeg and MKVToolNix online version selection/rollback remains available alongside MediaPrep version management.
- Added a non-interactive GitHub PowerShell web installer under `Installer\Install-MediaPrep-Web.ps1`, with `-InstallPath`, `-Force`, GitHub release discovery, SHA-256 verification when available, and ConstrainedLanguage-aware messaging.
- `Start MediaPrep.cmd` and the error-queue CMD launcher are stored without UTF-8 BOM so `cmd.exe` does not interpret BOM bytes as part of `@echo off`.
- Start Center now detects PowerShell ConstrainedLanguage before loading WinForms and shows a clear policy message before exiting.
- The interactive ZIP installer also detects ConstrainedLanguage before loading WinForms and points managed users to the web installer/policy requirement instead of failing with a type error.
- CPU/GPU verification now checks FFmpeg, FFprobe, and MKVToolNix first and directs the user to Settings → External tools when they are missing.
- Encoder failures are translated into clearer driver guidance. NVIDIA NVENC API/driver mismatches report the required driver/API when FFmpeg supplies them; Intel QSV and AMD AMF driver/device failures also get targeted guidance.
- Added independent source-format checkboxes on Options: TS, MP4, AVI, MPG, MPEG, and MKV. The first five are enabled by default; MKV is opt-in. A queue cannot start if no format is selected.
- MKV can now be selected as an input format. Selected MKV sources skip remuxing, go directly to analysis/optional HEVC encoding, and use verification/restart-safe staging before the source is removed.
- UNC MKV sources are handled safely when the source and final output have the same path: the verified result replaces the original atomically when deletion is enabled; with deletion disabled the original is preserved and the result is published as `name.mediaprep.mkv`.
- The working CPU/GPU layout fix from 0.11.51 is preserved unchanged.

## 0.11.51 - 2026-08-11

- CPU/GPU layout: fixed WinForms anchoring that moved Check CPU/GPU, Refresh hardware, the progress bar, and the details panel far outside the visible area when the container changed size.
- The affected controls are now left-anchored and retain their intended positions: check button X=682, refresh button X=900, and details panel X=682.
- No changes to encoder testing, capability cache, benchmarks, queue engine, muxing, encoding, UNC flow, or statistics.

## 0.11.50 - 2026-08-11

- CPU/GPU: the check button is explicitly visible and exists only on the CPU/GPU tab.
- CPU/GPU: the details panel is now a dedicated GroupBox that always displays benchmark and capability results for the selected or currently tested encoder.
- Banner: MediaPrep processes are displayed in two columns with name and PID for improved readability.

# MediaPrep MKV Toolkit Changelog

## 0.11.49 - 2026-08-11
- The CPU/GPU check is now available only on the **CPU/GPU** tab. The global check button at the bottom of Start Center has been removed.
- The banner displays the installed **FFmpeg version** and **MKVToolNix version**.
- The banner continuously displays the name and PID of the Start Center process and all active child processes started from it, such as PowerShell, FFmpeg, ffprobe, and mkvmerge. The process list is refreshed approximately every five seconds.
- The tool manager can now retrieve and select from the five most recent available stable FFmpeg versions online. The selected version is staged and compatibility-tested before activation.
- The tool manager can select from the five most recent MKVToolNix versions online.
- Existing local rollback is retained: the active version is backed up before replacement, allowing a previously working FFmpeg/MKVToolNix version to be restored even after another online version has been installed.
- **A / all** installs the latest version of both tools; **F** and **M** open the respective version selectors.
- Changing FFmpeg continues to invalidate the CPU/GPU verification so encoders are reverified against the selected FFmpeg version.
- No changes to queue isolation, muxing, analysis, encoding algorithm, error queue, session statistics, or UNC return handling.

## 0.11.45 - 2026-08-11
- The CPU/GPU tab now also displays detected NVIDIA, Intel, and AMD encoder candidates **before** the first check. They are clearly marked as `Not checked`; they are not approved or stored as the active encoder until the actual benchmark/capability test succeeds.
- When queue startup is blocked because CPU/GPU has not yet been checked, Start Center switches to the CPU/GPU tab and focuses **Check all encoders**.
- Start Center now has a fixed window size and can no longer be resized so small that CPU/GPU buttons, tabs, or bottom controls fall outside the visible layout. Normal minimization to the taskbar remains available.
- Encoder, queue, mux, analysis, statistics, theme, UAC, and tool-management logic is otherwise unchanged.

## 0.11.44 - 2026-08-11
- Hotfix: Start Center could not open because of incorrect use of PowerShell's `-f` operator in the CPU/GPU tab text for physical cores/logical processors.
- The CPU row is now formatted before being passed to `List.Add()`, preventing the hardware summary from producing a `FormatError` during startup.
- No queue, mux, analysis, NVENC/QSV/AMF, statistics, UAC, theme, or tool-management logic was changed in this hotfix.

## 0.11.43 - 2026-08-11
- Added a new **CPU/GPU** tab between Options and Settings. It displays detected CPU/GPU hardware, drivers, verified HEVC encoders, and benchmark results.
- A first installation selects CPU/libx265 by default. A real CPU/GPU verification must be completed before a queue can start.
- Encoder verification runs reproducible 1080p test encodes and verifies only backends that are both present in FFmpeg and supported by installed hardware: CPU/libx265, NVIDIA/hevc_nvenc, Intel/hevc_qsv, and AMD/hevc_amf.
- Multiple verified encoder alternatives can be selected from a dropdown while the queue is stopped. The encoder cannot be changed while a queue is running.
- Benchmarks display speed, SSIM, and test size. For NVIDIA, VRAM before/maximum/increase, GPU/encoder utilization, and temperature are also measured when `nvidia-smi` is available. VRAM is diagnostic only and is not user-controlled.
- NVIDIA capability testing covers CUDA decode, preset P4, VBR/CQ, Spatial AQ, Temporal AQ, lookahead, surfaces, and multipass, among other features. Features that fail the real test are marked unsupported. Main encoding retains the conservative/stable NVENC profile and does not automatically enable new optional features.
- Encoder results are stored in `Data\encoder-capabilities.json` and `Data\encoder-benchmark.json`. Verification becomes stale if the FFmpeg version, GPU list, or graphics driver changes.
- The banner dynamically displays the selected encoder, for example CPU HEVC, NVIDIA HEVC NVENC, Intel HEVC QSV, or AMD HEVC AMF.
- FFmpeg and MKVToolNix updates now back up the active version under `Tools\ToolBackups`. The tool manager includes **Versions/restore** and can restore a previous local version if an update causes problems.
- FFmpeg is updated through staging and verified before activation. Failed activation automatically restores the previous version. Changing FFmpeg invalidates the CPU/GPU verification.
- The Custom theme's three hex fields now have compact live color previews beside each value. The preview changes immediately when a valid `#RRGGBB` value is entered. Saving Custom colors restarts Start Center while the queue is stopped so the theme is applied immediately.
- Green/red path and program status indicators are restored after theme application so their semantic status colors are retained.
- Theme/language restart uses the normal UAC startup logic, so a saved Windows Update protection setting does not lose elevation after a theme change.
- Work queue, queue isolation, error queue, session statistics, saved queue packages, UAC/Windows Update protection, file formats, and dashboard are unchanged except that the selected encoder is passed through the job file.

## 0.11.42
- The work queue uses a single vertical button column in both Queue and All-in-one modes.
- Added a theme selector under Settings: Light, Dark, By month, and Custom.
- By month automatically selects the color palette associated with the current month.
- Custom stores three hex colors: banner, secondary/panel, and background.
- The theme is also used by the queue monitor/statistics window.

## 0.11.41 - 2026-08-11
- UI: unchecked checkboxes and radio buttons are displayed with gray text but remain clickable; selected choices are displayed in black.
- UAC: Windows Update protection can be selected even when Start Center is not elevated; UAC is requested only when the setting is saved.
- UI: a UAC shield is displayed before the Windows Update protection option.
- Work queue: "Load..." has been renamed to "Add to queue".
- Work queue: the Logs button has moved from Queue/All-in-one to Settings under View statistics.
- Queue monitor: the bottom-row status and buttons no longer overlap; Show/Hide details remains fully visible when resized.

## 0.11.40 - 2026-08-11

- All-in-one: cleaned up the two-column work-queue button layout so controls do not overlap or get clipped.
- Save queue / Open queue are now available in both Queue and All-in-one modes.
- The Options tab was reorganized: run mode and encoding criteria are at the top, with remaining options grouped below.
- UAC: MediaPrep normally starts without administrator rights. Elevation is requested only when the user explicitly saves "Prevent automatic Windows Update restart during the queue".
- Windows Update restart protection is disabled on first startup.
- When protection is enabled and settings are saved, Start Center restarts through UAC; the current queue list is saved before restart.
- Windows Update protection cannot be changed/saved while a queue is running; the user receives a clear message instead of a restart.
- Archived statistics: old stage 8/9 entries with a documented successful return copy are reconstructed as completed, stabilizing the progress bar and "Completed" count.
- Session statistics: an Out-copy no longer marks `Result=Completed` before QueueStage 10 has actually been written.

## 0.11.39 - 2026-08-11

- The session clock starts only when the queue starts and counts only active queue time; it does not run merely because Start Center is open.
- All queues are registered in session statistics at startup, rather than only when each queue begins processing.
- The statistics window's old `Refresh now` action is replaced with **Load statistics...** and **Current**. Archived statistics-run JSON files can be displayed, including remaining/error/slow-copy data.
- Start Center adds **Save queue** and **Open queue**. The queue package is a ZIP containing relevant JSON files, including session statistics.
- At startup, an unfinished session is detected and the user can choose Continue, Save for later, or Delete.
- The session file is archived only when Start Center closes normally and no queue process is still running.

## 0.11.38 - 2026-08-10

- Fixed dashboard errors for large byte values above the Int32 limit (2,147,483,647).
- Space savings are now calculated using Double/64-bit size values without the `Math.Max(Int32)` overload.
- The dashboard can therefore continue updating statistics for large queues/files without the error "Cannot convert ... to System.Int32".

## 0.11.36 - 2026-08-10
- Added a clean directory layout: executable PowerShell scripts are stored under `App\`; the root folder contains only the launcher and documentation.
- `config.json` and `mediaprep.preferences.json` are stored under `Data\`.
- Start Center automatically migrates older root scripts to `Data\LegacyLayoutBackup_*` and moves older configuration files into `Data\` when required.
- All internal paths were reviewed for the App/Data layout: Start Center, Queue Host, Queue, Dashboard, MediaPrep, tool manager, installer, and error-queue batch file.
- Session statistics store every actual copy as a `CopyEvent`; if the same file is copied again during the same session, the new transfer is counted as well.
- `Total copied from UNC`, `Total copied back`, copy time, and MB/s are aggregated from all copy events in the session.
- The dashboard's main progress bar displays completed files / all registered files across the entire session.
- A dashboard log is always created for INFO/WARN/ERROR; Verbose adds only VERBOSE entries.
- JSON writes in the main engine and Start Center are atomic through a temporary file to reduce the risk of the dashboard reading a partially written session/queue file.
- The installer copies only program files and default configuration, never existing media, logs, queue data, or statistics data.

# Changelog

## 0.11.35 - 2026-08-10
- Added a new session-based statistics file: `Data\statistics-run-current.json`.
- The statistics session is created when Start Center opens and persists across multiple queue runs until Start Center closes.
- Every UNC queue and file is added to the same session file with inbound/outbound copy information, sizes, results, and queue status.
- The Run statistics tab uses the session file as its source of truth and therefore does not reset between individual UNC queues.
- `Average in` and `Average back` are calculated as total MB / actual total copy time for the entire session.
- When Start Center closes, the session is archived under `Data\Statistics`.
- If an old current file is found at startup, it is preserved as a recovered session before a new session is created.

## 0.11.35

- UNC queues are now strictly isolated: one queue item is copied, muxed, analyzed, encoded, and returned before the next queue item starts.
- In queue mode, `Scan-MediaLibrary` is limited to only the local source files imported for the current UNC queue.
- MKV analysis and NVENC recommendations are limited to ExpectedOutput files belonging to the current UNC queue.
- Old/resumed local files from other queue items can no longer be pulled into the current processing run.
- This reduces the risk of `UnProcessed`/`Processed` filling local disk space when many UNC folders are queued.

## 0.11.33

- Fixed a queue-stopping condition where a broken or old local AVI/MPG/MPEG/TS/MP4 file in `UnProcessed` could abort all subsequent UNC queues during the ffprobe stage.
- `ffprobe` is now started through `System.Diagnostics.Process`, so stderr from an invalid media file does not become an unintended `NativeCommandError` in Windows PowerShell 5.1.
- If ffprobe cannot analyze a local source file, the working copy is moved to `Error`, registered as `SourceProbe` in the error queue, and the main queue continues with the next file. The UNC original is not affected.
- The error reason now contains ffprobe's actual exit code and error text for easier troubleshooting.

## 0.11.32
- Fixed false "UNC copy has no video stream" errors for valid MPG/MPEG-to-MKV conversions through ffprobe JSON verification.
- Distinguishes ffprobe errors from genuinely missing video/audio streams.
- UNC return-copy failures store `ErrorKind`/`PreviousStage`/`LocalPath` so a locally working MKV can be reviewed.
- **Continue** restores publishing errors to QueueStage 8 (Waiting for return copy) instead of remuxing/reanalyzing.
- Error-queue buttons now sit in their own docked button row and can no longer be covered when the table is resized.
- Inventory-based errors display `LocalOutput`/`ErrorLocalPath` in the Error path column.

## 0.11.31

- Fixed the dashboard error `The property 'Sum' cannot be found on this object`.
- The queue monitor defensively sums copied bytes/times row by row and works even before `queue-copy-stats.json` has been created.
- Average copy speed is calculated without `Measure-Object` for better PowerShell 5.1 compatibility.
- Missing runtime JSON files are logged only once and logged again when they appear.

# Changelog

## 0.11.30

- The error-queue view provides three manual actions for each selected file: **Review**, **Continue**, and **Delete**.
- Review opens the local muxed MKV file with the Windows default player.
- Continue removes the error entry and restores the item to the safest QueueStage based on local files and ffprobe (HEVC => Encoded, other MKV => Muxed, local source => Local source ready).
- Delete removes the item from both the error queue and the full queue inventory and deletes local work/temp files. The UNC original is never touched.
- Manual error-queue actions are written to the dashboard verbose log.

## 0.11.29
- Fixed QueueStage matching after muxing: sources such as `.ts`, `.mp4`, `.avi`, `.mpg`, and `.mpeg` are now matched to the corresponding `.mkv` item using the same relative base name.
- The error-queue view now reads `Data\error-queue.json` directly and supplements it with QueueStage 90–92 so encoder errors are visible even if a status update was missed.
- The queue monitor gets a separate **Ready to move** counter for QueueStage 8.
- **Remaining in queue** continues to count all unfinished items across all UNC queues.
- Dashboard JSON reading is more tolerant of missing/null fields to prevent the entire refresh from failing.

## 0.11.28 - 2026-08-10

- Moved **View statistics** to Program settings under Settings.
- Hides Start Center's empty PowerShell host window.
- Hides the queue monitor's empty PowerShell host window.
- Starts the detailed Queue Host console window hidden.
- Added **Show details / Hide details** in the queue monitor to toggle the Queue Host console when needed.
- Queue Host publishes its window handle locally in `Data\queue-console-window.json` while running.
- Verbose logs continue to work even when the console windows are hidden.

# 0.11.27

## 0.11.27 - 2026-08-10

- Fixed a ParserError in `MediaPrep-Queue-Dashboard.ps1` where literal `` `r`n `` sequences had ended up in the script code.
- The queue monitor can once again be started automatically from Start Center.
- When **Verbose logging** is enabled, the queue monitor gets its own log: `Loggar\MediaPrep-Queue-Dashboard_YYYY-MM-DD_HH-mm-ss.log`.
- The dashboard log records startup/shutdown, JSON read errors, layout errors, and refresh errors.
- Start Center also writes `Loggar\MediaPrep-Queue-Dashboard-Launcher.log` in verbose mode to troubleshoot the startup of the statistics process itself.
- Retains support for `.ts`, `.mp4`, `.avi`, `.mpg`, and `.mpeg`.

# 0.11.26

## 0.11.26 - 2026-08-10
- Added `.mpg` and `.mpeg` as supported source formats throughout queue scanning, All-in-one, ffprobe analysis, muxing, and summaries.
- Fixed regression where the queue statistics window did not always open automatically when starting the queue.
- Queue dashboard launch now uses a single quoted Windows PowerShell 5.1 argument string with `-STA`, preserving paths that contain spaces.
- Start Center now reports the dashboard process PID on successful launch and shows an explicit error if the dashboard cannot be started.

- Fixed the queue monitor where columns shrank during every one-second refresh.
- DataGridView now uses fixed column widths; only the path/start column adapts when the window is resized.
- Dashboard refresh itself no longer changes the column layout.

# Changelog

## 0.11.25 - 2026-08-10
- Added full `.avi` source-format support alongside `.ts` and `.mp4`.
- Source files are analyzed with `ffprobe` before muxing.
- ffprobe results include container, video/audio codec, profile, pixel format, resolution, FPS, duration, bitrate, and stream count.
- Probe data follows the scan item and is stored in the queue dashboard when the file enters the mux stage.
- AVI uses the same subtitle, mux, analysis, NVENC, error-queue, and UNC workflow as the other source formats.

## 0.11.22 – 2026-08-10

- Added a separate queue-monitor window that opens automatically when the queue starts.
- Added a **View statistics** button in Start Center to reopen the queue monitor.
- The queue monitor reads local `Data\queue-dashboard-inventory.json` and does not need to read UNC paths to display statistics.
- `queue-dashboard-inventory.json` version 2 now contains `errors` and `items`.
- The queue monitor has views for **Remaining in queue**, **Error queue**, **Run statistics**, and **Slow copies**.
- The Error queue view has a **Process error queue** button that manually starts tolerant decoding.
- Copying from UNC and back to UNC is timed per video file with bytes, time, and MB/s in `Data\queue-copy-stats.json`.
- Queue start/end is stored in `Data\queue-run-current.json` with start time, end time, and total run time.
- Slow copies are flagged when they fall below 30 MB/s or below 50% of the current average speed.

## 0.11.20 – 2026-08-10

- Moved queue statistics into a dedicated fixed GroupBox in the upper-right section of Work queue, above the queue list.
- Statistics labels are created immediately with zero values and remain visible in Queue mode before inventory begins.
- Retains incremental statistics updates as valid files are found and when the queue changes.
- Clarified verbose STALL WARNING reporting when both media time and FFmpeg CPU time remain unchanged.

## 0.11.19 – 2026-08-10

- Queue statistics are now built with fixed labels directly in Overview and remain visible in Queue mode.
- Statistics update incrementally during UNC inventory and when the queue changes.
- Verbose logging now displays FFmpeg CPU-time delta, working memory, thread count, and how long media time has remained stalled.
- Verbose logging writes STALL WARNING when media time has not advanced for at least 20 seconds, together with a GPU snapshot.

## 0.11.18 – 2026-08-10

- Queue statistics remain visible in Queue mode and are kept in front in Start Center.
- Statistics update when the queue changes and incrementally during UNC inventory.
- Verbose logging is now passed through to the MediaPrep process.
- Verbose logging records the full FFmpeg command line, FFmpeg version, NVENC parameters, and GPU snapshots before/after each encode.
- GPU snapshots include driver, P-state, temperature, GPU/encoder utilization, and clock frequencies.

## 0.11.17 – 2026-08-10

- Queue statistics are always displayed in both Queue and All-in-one modes.
- Queue statistics are recalculated immediately when items are added, removed, or moved.
- UNC inventory updates statistics for every valid TS/MP4 file found.
- All-in-one also displays remaining subtitles and the number of completed MKV files.

## 0.11.16 – 2026-08-10

- The queue status row now displays only whether the queue is running.
- File name and next queue item have been removed from Overview.
- Counts, size, and return-copy status are displayed only in Queue statistics.

## 0.11.15 – 2026-08-10

- Start entire queue now prechecks all UNC folders before the batch begins.
- If UNC access is missing, authentication is presented in the elevated MediaPrep session and the SMB connection is established there.
- Each UNC queue folder is verified for read, write, and delete access using a temporary access-test file.
- Queue statistics are simplified to remaining files, processed across the full queue, remaining size, and ready for return copy.
- Queue-statistics labels are always visible in Queue mode.
- Language files version 1.3.8.

## 0.11.14 – 2026-08-10

- Added queue statistics to Overview: remaining video files, remaining size, subtitles, processed files, total count, and files ready for UNC return.
- Statistics build an inventory of the UNC queue and update automatically during processing.
- Cleanup of empty local folders now also includes `Processed`.
- Start Center 3.3.14 and language files 1.3.7.

## 0.11.13 – 2026-08-08

- Fixed NVENC progress in Windows PowerShell 5.1 by reading FFmpeg StandardOutput directly.
- The blue progress box now updates continuously from each complete `progress=continue` block.
- Progress is still logged every five seconds without purple console lines.

## 0.11.12 – 2026-08-08

- NVENC progress is now read continuously through `-progress pipe:1` instead of a direct progress file that could be buffered until completion.
- The blue progress box displays file number, file name, media time, percentage, encoding speed, and estimated time remaining.
- `[PROGRESS]` is stored in the log file every five seconds but is no longer written as purple console lines.
- UNC import and UNC return display count, total count, percentage, and current file using the same extended progress format.

## 0.11.11 – 2026-08-08

- Displays continuous NVENC time, percentage, speed, and remaining time in the blue Write-Progress box for each file.
- Also writes a `[PROGRESS]` line to the console and log every five seconds.
- Displays copy progress when completed MKV files are returned to UNC.
- Cleans empty subfolders in `UnProcessed` and `Processed` after return copy and at queue completion.
- Cleanup also works when a previously interrupted batch is resumed; folders containing remaining files are left untouched.

## 0.11.10 – 2026-08-08

- Fixed a newly added UNC folder disappearing from the queue after approximately 1.5 seconds.
- The queue is now saved to the settings file immediately when a folder is added.
- The refresh timer can therefore no longer restore the list to an older empty queue.

## 0.11.9 – 2026-08-08

- Fixed UNC return after restart when `LocalVideo` is empty for files already present in `Processed`.
- Empty paths are checked before calling `Test-Path`.
- Added machine-readable FFmpeg progress during NVENC encoding.
- Writes `[PROGRESS] processed/total | percentage | speed | remaining` every five seconds to the console and log.

## 0.11.8 – 2026-08-08

- Made UNC import restart-safe after interrupted muxing or NVENC encoding.
- Skips UNC copying when the corresponding MKV already exists in `Processed` and the local source is missing.
- Reuses a complete file in `UnProcessed` when its size matches the UNC original.
- Re-copies local or temporary copies that have the wrong size.
- Forces a new mux when both the local source and corresponding MKV exist, because the previous processing is then considered incomplete.
- Stores restart status in the UNC import manifest.

## 0.11.7 – 2026-08-08

- Fixed a Windows PowerShell 5.1 error in path and program verification.
- Generic lists are now counted and iterated directly without array conversion.
- Retains green check marks and red crosses for all folders and program files.
- Updated language files to version 1.3.6.

## 0.11.6 – 2026-08-08

- Displays a green check mark or red cross for all configured folders and programs.
- Renamed the button to "Check paths / programs".
- Verification covers the installation folder, work folders, data folders, and external programs.
- Status updates at startup, after selecting a path, after saving, and during manual verification.
- Updated language files to version 1.3.5.

## 0.11.5 – 2026-08-08

- Fixed a startup error where the status check was used before it had been created under StrictMode.
- Moved the first tool-status refresh until after the status field has been created.
- Made the status function safe during early initialization.

## 0.11.4 – 2026-08-08

- Moved the "External tools" heading to the left column between folders and tool paths.
- Removed the large external-tools status box from the right column.
- Gave the language field and tool buttons fixed widths so button labels are more visible.
- Adjusted the Settings layout to give the right column more space.

# Changelog

## 0.11.3 – 2026-08-08

- Restored default tool paths to `Tools\FFmpeg` and `Tools\MKVToolNix`.
- Split Preferences into a compact left panel and a separate panel for application language and tool management.
- Displays status and path for FFmpeg, FFprobe, and MKVToolNix.
- Updated language files to version 1.3.4.

# Changelog

## 0.11.3 – 2026-08-08

- File pickers for ffmpeg.exe, ffprobe.exe and mkvmerge.exe now open in the directory already configured in Preferences.
- If the configured file does not exist, the nearest existing parent directory is used.
- Language selection is kept visible in Preferences and remains available after adding the external tool manager.
- Language files updated to version 1.3.3.

# Changelog

## 0.11.3 – 2026-08-08

- Keeps a single universal launcher: `Start MediaPrep.cmd`.
- Adds `Manage-MediaPrepTools.ps1`.
- Adds tool detection, version checks and hardware encoder capability checks.
- Adds download/update support for FFmpeg and MKVToolNix from configured project distribution sources.
- Prevents queue start when required tools are missing and offers to open the tool manager.

# Changelog

## 0.11.0 — 2026-08-08

- Renamed the product to **MediaPrep MKV Toolkit**.
- Changed the default input folder from `Filmer` to `UnProcessed`.
- Preserved compatibility with existing installations that explicitly use `Filmer`.
- Kept the project PowerShell-based with no compiled MediaPrep executable.
- Added a PowerShell installer with a selectable installation folder.
- Added the complete folder structure to the distribution, including empty folders through `.gitkeep`.
- Added `LICENSE.md` for personal, non-commercial source-available use.
- Added `THIRD-PARTY-NOTICES.md` and confirmed that third-party binaries are not bundled.
- Updated language files to version 1.4.0.
