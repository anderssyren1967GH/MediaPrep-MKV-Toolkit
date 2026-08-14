# Third-party licenses and distribution boundary

Checked for MediaPrep MKV Toolkit 0.11.54 on 2026-08-14.

MediaPrep itself is licensed under **GPL-3.0-or-later**. Third-party projects are not covered by the MediaPrep copyright license; each keeps its own license and, where applicable, separate patent/standards terms.

## What the MediaPrep ZIP contains

The official full/update MediaPrep ZIPs contain MediaPrep source code, language resources, documentation, artwork and empty runtime folders. They **do not contain FFmpeg, ffprobe or MKVToolNix binaries**.

This separation is deliberate: it makes it clear which code Anders Syrén licenses as MediaPrep and which tools are obtained separately under their own terms.

## FFmpeg / ffprobe

MediaPrep can use a user-supplied FFmpeg installation. Its external-tool manager can also download the **Gyan FFmpeg release essentials** Windows build.

Important license facts:

- The FFmpeg project is LGPL-2.1-or-later by default; enabling GPL components makes a particular FFmpeg build GPL.
- Gyan states that its current Windows builds are **GPLv3** static builds.
- Gyan's essentials build currently includes `libx264`, `libx265`, `libaom` and hardware-support libraries/interfaces for AMF, CUDA/NVENC and Intel VPL/QSV.
- MediaPrep does not claim ownership of, or relicense, those components.
- MediaPrep must not use or recommend an FFmpeg build configured with `--enable-nonfree` for a redistributable/open workflow.

Project/source references:

- FFmpeg legal/licensing: https://ffmpeg.org/legal.html
- FFmpeg source license: https://ffmpeg.org/doxygen/7.0/md_LICENSE.html
- Gyan Windows builds: https://www.gyan.dev/ffmpeg/builds/

## MKVToolNix / mkvmerge

MediaPrep uses `mkvmerge` as an external executable. MKVToolNix is a separate GPL-licensed project and includes additional third-party components under their respective licenses. MediaPrep does not relicense MKVToolNix.

Project/source references:

- Project/downloads: https://mkvtoolnix.download/
- Upstream project information: https://www.bunkus.org/videotools/mkvtoolnix/

## GPU/accelerator interfaces

MediaPrep currently reaches NVIDIA NVENC, Intel QSV/VPL and AMD AMF through FFmpeg. MediaPrep does not bundle the GPU vendor SDKs.

- **NVIDIA Video Codec SDK / NVENC:** NVIDIA's SDK license grants a royalty-free, fully paid-up license for the licensed SDK materials subject to its terms, but NVIDIA explicitly states that third-party codec/patent licenses are separate.
- **Intel oneVPL / QSV:** the oneVPL project is MIT-licensed. Codec/standard patent questions are separate from the API software license.
- **AMD AMF:** the AMF SDK is MIT-licensed. AMD explicitly states that it does not grant a license to codec-standard patent rights; those rights must be considered separately.

References:

- NVIDIA Video Codec SDK license: https://developer.nvidia.com/nvidia-video-codec-sdk-license-agreement
- Intel oneVPL: https://github.com/intel/libvpl
- AMD AMF: https://github.com/GPUOpen-LibrariesAndSDKs/AMF

## Codec patents are not the same thing as software licenses

A free/open-source encoder implementation does **not automatically mean that every patent right in the encoded format is royalty-free**. This distinction is especially important for H.264/AVC and H.265/HEVC.

For the lowest licensing friction when adding a new codec profile, MediaPrep should prefer codecs designed around a royalty-free patent policy, while still keeping normal legal disclaimers and preserving all required notices.

See [`ENCODER-LICENSING.md`](ENCODER-LICENSING.md) for the encoder-by-encoder assessment.

This document is a technical licensing inventory, not legal advice.
