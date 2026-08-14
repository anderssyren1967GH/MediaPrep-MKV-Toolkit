# Encoder and codec licensing notes

Checked for MediaPrep MKV Toolkit 0.11.54 on 2026-08-14.

## Short answer

**“Free encoder” and “royalty-free codec” are not the same thing.** MediaPrep should document both layers separately.

For a future new encoding profile, **AV1 is the strongest fit for the goal of minimizing codec-license/royalty uncertainty** because the Alliance for Open Media publishes AV1 under its royalty-free patent policy and Open Media Patent License. MediaPrep 0.11.54 does **not** enable AV1 encoding; this document is an assessment only.

## Current MediaPrep HEVC encoders

MediaPrep currently verifies these HEVC paths:

| MediaPrep path | Encoder/API software status | Codec/patent status | MediaPrep position |
|---|---|---|---|
| `libx265` | Open-source implementation; the Gyan FFmpeg essentials build that MediaPrep can download is GPLv3 | HEVC patent rights are separate from the x265/FFmpeg software license | Keep supported, but **do not label HEVC “license-free”** |
| `hevc_nvenc` | NVIDIA hardware encoder accessed through FFmpeg; NVIDIA's SDK materials are licensed royalty-free under the SDK agreement | NVIDIA states that third-party codec patent rights are separate | Keep supported; do not claim codec royalty freedom |
| `hevc_qsv` | Intel QSV/VPL path; oneVPL project is MIT-licensed | Codec patent rights are separate from the API software license | Keep supported; do not claim codec royalty freedom |
| `hevc_amf` | AMD AMF is MIT-licensed | AMD explicitly says its software does not grant codec-standard patent rights | Keep supported; do not claim codec royalty freedom |

This distinction matters even when MediaPrep itself is free/open-source.

## AV1 candidates with lower licensing friction

### 1. `libaom-av1` — strongest immediate software candidate

- `libaom` is the Alliance for Open Media reference implementation.
- Source files are distributed under a BSD-style software license together with the Alliance for Open Media Patent License 1.0.
- The AOM patent license grants a no-charge, royalty-free license to licensors' Necessary Claims subject to its conditions.
- FFmpeg supports AV1 encoding through `libaom`.
- The Gyan **essentials** Windows build currently used by MediaPrep's download helper includes `libaom`, so this candidate does not require changing to the larger FFmpeg full build.

**Assessment:** preferred first AV1 software encoder to test in MediaPrep.

### 2. `libsvtav1` — strong software candidate if distribution source changes

- SVT-AV1 is an AOMedia AV1 encoder.
- Current SVT-AV1 versions are published under the BSD 3-Clause Clear License together with the Alliance for Open Media Patent License 1.0.
- FFmpeg supports `libsvtav1`.
- Gyan's current **full** build includes `libsvtav1`, while its essentials build does not.

**Assessment:** attractive for performance/quality, but adopting it with the current helper would require either moving from the essentials build or supplying another verified source. Do not change this just for licensing.

### 3. AV1 hardware encoders

Potential FFmpeg paths include `av1_nvenc`, `av1_qsv` and `av1_amf` on supported hardware/drivers.

- The hardware API/software license and the AV1 codec patent license are separate layers.
- AV1's AOM patent framework is the reason AV1 is preferable from a royalty-policy perspective; the GPU vendor API license alone is not what makes AV1 royalty-free.
- Hardware support varies by GPU generation and must be verified by a real encode test, just as MediaPrep already does for HEVC.

**Assessment:** suitable future optional encoders after compatibility testing.

## Why MediaPrep should not switch codecs blindly

Licensing is only one requirement. Before AV1 becomes a normal MediaPrep output option we should verify:

1. Plex server direct-play/transcode behavior.
2. The actual Google TV / playback-client AV1 decoding support.
3. MKV compatibility with the target clients.
4. Encode speed and quality on CPU vs NVIDIA/Intel/AMD hardware.
5. File-size savings compared with the current HEVC targets.
6. Subtitle/audio behavior and MediaPrep's existing restart-safe queue guarantees.

Therefore 0.11.54 **documents AV1 but does not change the working HEVC pipeline**.

## Terms MediaPrep should use

Preferred wording:

- **“royalty-free patent policy”** for AV1/AOM where supported by the AOM license.
- **“open-source/free software encoder implementation”** for software such as libaom or SVT-AV1.
- **“royalty-free SDK/API license”** when a vendor license says that about its SDK/API.

Avoid blanket wording such as:

- “all encoders are license-free”;
- “HEVC is royalty-free”;
- “using NVENC/QSV/AMF automatically covers codec patents”.

## Primary references

- Alliance for Open Media patent license: https://aomedia.org/license/patent-license/
- Alliance for Open Media legal overview: https://aomedia.org/about/legal/
- libaom source/patent notices: https://aomedia.googlesource.com/aom/
- SVT-AV1: https://gitlab.com/AOMediaCodec/SVT-AV1
- FFmpeg external-library documentation: https://github.com/FFmpeg/FFmpeg/blob/master/doc/general_contents.texi
- NVIDIA Video Codec SDK license: https://developer.nvidia.com/nvidia-video-codec-sdk-license-agreement
- Intel oneVPL: https://github.com/intel/libvpl
- AMD AMF: https://github.com/GPUOpen-LibrariesAndSDKs/AMF
- Gyan FFmpeg Windows builds: https://www.gyan.dev/ffmpeg/builds/

This is a technical licensing assessment, not legal advice. Patent rules can vary by jurisdiction and use case.
