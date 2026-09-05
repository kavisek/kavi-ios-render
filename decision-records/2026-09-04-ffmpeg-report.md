# FFmpeg Evaluation Report

- **Date:** 2026-09-04
- **Status:** Draft / Informational
- **Author:** Kavi (via Claude Code)

## Context

This repository (`kavi-ios-render`) is currently a fresh project with no established
architecture yet. As part of early tooling decisions, this report evaluates **ffmpeg**
as a general-purpose candidate for audio/video processing (transcoding, muxing,
thumbnailing, format conversion, etc.), since these are common needs for an "iOS
render" pipeline. No specific use case or requirement has been locked in yet — this
is a general capability/tradeoff survey to inform a future, more specific decision.

## What is FFmpeg

FFmpeg is a free, open-source, cross-platform suite of libraries and command-line
tools for handling multimedia: encoding, decoding, transcoding, muxing/demuxing,
streaming, filtering, and playback. It is one of the most widely adopted multimedia
toolkits in the industry, underlying tools like VLC, HandBrake, and countless server
and mobile media pipelines.

Core components:
- **libavcodec** — encoders/decoders for audio/video codecs (H.264, HEVC, VP9, AAC, etc.)
- **libavformat** — muxing/demuxing for containers (MP4, MOV, MKV, HLS/DASH segments, etc.)
- **libavfilter** — filter graphs (scaling, cropping, overlays, color correction, etc.)
- **libswscale / libswresample** — pixel format/color space and audio resampling conversion
- **ffmpeg** (CLI) — command-line front-end built on the above libraries
- **ffprobe** — media inspection/metadata extraction tool

## Technology Stack

FFmpeg is written almost entirely in **C** (C89/C99), which is central to why it
runs virtually everywhere:

- **Core libraries (libavcodec, libavformat, libavfilter, libswscale, libswresample,
  libavutil, libavdevice)** — pure C, with no required external runtime, making it
  portable to embedded systems, mobile OSes, and servers alike.
- **Assembly (x86 SIMD, ARM NEON, etc.)** — hand-written and generated (via the
  `x86asm`/`checkasm` tooling) assembly for hot paths like pixel/motion-vector
  operations, critical to real-time encode/decode performance.
- **Build system** — a custom `configure` script (shell/Make-based, not
  autotools/CMake), reflecting the project's long history and its need for
  fine-grained control over which codecs/formats/hardware backends are compiled in.
- **Optional third-party codec libraries** — FFmpeg itself implements many codecs,
  but can optionally link against external libraries for others, e.g. `libx264`
  (H.264, GPL), `libx265` (HEVC, GPL), `libvpx` (VP8/VP9), `libopus`/`libmp3lame`
  (audio), `libaom` (AV1). These are the source of most GPL entanglement noted
  above — the FFmpeg core itself is LGPL.
- **Hardware acceleration bindings** — VideoToolbox (Apple), VAAPI/VDPAU (Linux),
  NVENC/NVDEC (NVIDIA), MediaCodec (Android), etc., are integrated as thin C
  wrappers around each platform's native hardware codec APIs.
- **CLI tools (`ffmpeg`, `ffplay`, `ffprobe`)** — also C, built as thin
  application layers on top of the library stack.
- **iOS-specific builds** distribute the C libraries as compiled `.xcframework` /
  `.framework` bundles (e.g. via `ffmpeg-kit`), since Swift/Objective-C projects
  cannot consume raw C source directly without a bridging build step.

The choice of C (rather than C++ or a higher-level language) is deliberate and
long-standing: it maximizes portability across compilers/platforms, avoids
ABI/runtime overhead, and gives predictable performance for pixel-level
processing — all priorities for a multimedia library meant to run on everything
from routers to phones to servers.

## Development History

- **2000** — FFmpeg was started by **Fabrice Bellard** (later known for QEMU and
  TCC) as a small transcoding tool. The name combines "FF" (moving picture experts
  group's "Fast Forward") with "MPEG."
- **2004** — Bellard stepped back from active maintenance; **Michael Niedermayer**
  became the primary maintainer for over a decade, during which the project grew
  into the de facto standard multimedia library used across the open-source
  ecosystem.
- **2011 — The Libav fork**: a group of FFmpeg developers forked the project as
  **Libav**, citing disagreements over project governance and code review process.
  For several years both projects existed in parallel, with distributions like
  Debian and Ubuntu at one point shipping Libav instead of FFmpeg.
- **2011–2014** — Development happened somewhat divergently across both projects,
  with patches occasionally cherry-picked between them. This period is often cited
  as a case study in open-source governance conflicts.
- **~2014–2015** — Momentum shifted decisively back to FFmpeg: major distributions
  (Debian, Ubuntu) switched back to FFmpeg, and most active development
  consolidated there. Libav has been effectively dormant since.
- **2015–present** — Continued community-driven development under a rotating group
  of maintainers (no single BDFL), with contributions from major industry players
  (Google, since it underlies parts of Chrome/Android media handling; various CDN
  and streaming companies) alongside independent contributors. Ongoing work has
  added modern codec support (AV1, VVC/H.266 in progress), hardware acceleration
  backends, and streaming protocol support (HLS, DASH, WebRTC-adjacent tooling).
- **Governance today** — FFmpeg is maintained via a public mailing list and Git
  repository (no corporate owner), with a defined set of area maintainers; releases
  follow a versioned schedule (e.g. 5.x, 6.x, 7.x series) roughly annually.

This history is relevant to the licensing discussion above: FFmpeg's LGPL/GPL
dual-licensing model and its patchwork of optional codec dependencies are a direct
result of 25+ years of community-driven, incrementally-assembled development rather
than a single vendor's coordinated design — which is part of why licensing due
diligence (see below) requires checking the actual build configuration rather than
assuming a single blanket license applies.

## Licensing

- Core FFmpeg is licensed under **LGPL v2.1+**, or **GPL v2+** if built with
  GPL-licensed components (e.g. libx264, libx265).
- LGPL builds can generally be linked into proprietary/closed-source apps (including
  App Store apps) provided dynamic linking and license/attribution obligations are met.
- GPL builds impose copyleft requirements that are typically **incompatible** with
  closed-source App Store distribution unless the whole app is open-sourced.
- **Patent-encumbered codecs** (H.264, HEVC/H.265, AAC) may require separate patent
  licensing (e.g. via MPEG-LA/Access Advance) depending on distribution volume and
  business model — this is independent of FFmpeg's own license and applies to any
  codec implementation, not just FFmpeg's.
- **Action item if pursued:** confirm which build configuration (LGPL-only vs. GPL
  components) is used, and verify codec patent licensing obligations for the target
  distribution model.

## Relevance to an iOS render pipeline

Two broad integration paths exist:

1. **Client-side (on-device, iOS)**
   - Use a precompiled FFmpeg framework (e.g. via `ffmpeg-kit` or similar wrappers)
     linked into the app for local transcoding/rendering.
   - **Caveat:** `ffmpeg-kit` (the most widely used iOS/Android wrapper) was
     **retired/archived by its maintainer in 2025**; existing forks and mirrors exist
     but are community-maintained with unclear long-term support. This significantly
     raises the maintenance risk of a client-side FFmpeg dependency today.
   - iOS also has **native alternatives** (AVFoundation, VideoToolbox) that cover much
     of the transcoding/compositing surface without an external dependency, at the
     cost of less flexibility (fewer codecs/filters, more code to orchestrate complex
     pipelines).

2. **Server-side (backend render/transcode service)**
   - Run FFmpeg on a backend (or in a cloud function/container) that the iOS app
     calls into for heavier or more flexible media processing.
   - Avoids App Store binary size/licensing entanglement and sandboxing constraints.
   - Requires network round-trips and infrastructure (compute, storage, queueing) —
     not viable for pure offline/on-device rendering requirements.

## Tradeoffs Summary

| Factor | FFmpeg (client, on-device) | FFmpeg (server-side) | Native (AVFoundation/VideoToolbox) |
|---|---|---|---|
| Codec/format coverage | Very broad | Very broad | Narrower, iOS-native codecs |
| Maintenance risk | Moderate–high (ffmpeg-kit retired) | Low (you control the server build) | Low (Apple-maintained) |
| Licensing complexity | Real (LGPL/GPL + codec patents) | Same, but isolated from app binary | None (Apple-licensed) |
| Offline capability | Yes | No (needs network) | Yes |
| Binary size impact | Significant (multi-MB framework) | None | None |
| Hardware acceleration | Limited/software-focused unless configured | Depends on server hardware | Best (uses Apple hardware encoders) |
| Flexibility (filters, effects) | Very high | Very high | Lower, but sufficient for common cases |

## Recommendation

No decision is being made here — this is informational. If/when a concrete
requirement emerges (e.g. "transcode arbitrary user-uploaded video formats" or
"apply custom filter graphs not supported by AVFoundation"), the choice should be
revisited against that specific requirement. General guidance:

- Prefer **native AVFoundation/VideoToolbox** first for anything achievable within
  common iOS media formats — lowest risk, no licensing overhead, best performance.
- Reach for **FFmpeg server-side** if broader format/codec support or complex filter
  graphs are needed and an offline-only constraint doesn't apply.
- Treat **FFmpeg client-side (on-device)** as a last resort given the retirement of
  `ffmpeg-kit` and the associated licensing/maintenance overhead; if pursued, budget
  time to vet a maintained fork and confirm the license/patent posture explicitly.

## Open Questions

- What specific media operations does this project actually need (formats in/out,
  filters, real-time vs. batch)?
- Is offline/on-device processing a hard requirement, or is a backend acceptable?
- What are the App Store distribution constraints (closed-source vs. open-source)?
