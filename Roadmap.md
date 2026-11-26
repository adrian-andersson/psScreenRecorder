# psScreenRecorder v2 Roadmap

This file records the plan for rewriting psScreenRecorder, and the reasons behind it, so the work can pick up again without the original planning conversation.

The plan was agreed in November 2026. Version 1.0.8, published to PSGallery in June 2019, is tagged `v1.0.8`. Development continues on `main`, and `master` will be archived.

---

## Goals

- **Rewrite completely, as v2.0.0.** No compatibility with the 1.x commands is needed, except an alias for `convert-mp4togif`.
- **Let ffmpeg do the work.** PowerShell sets up the recording, then starts, stops and checks on ffmpeg. ffmpeg does the capturing and encoding.
- **Cross-platform from the start**: Windows, macOS and Linux (X11), on x64 and ARM64.
- **Tests from the start.** Pester tests sit next to each function, an integration suite runs on a synthetic video source, and CI covers several operating systems.
- **Never install or ship ffmpeg.** See [FFmpeg and licensing](#ffmpeg-and-licensing).
- Keep the module name `psScreenRecorder` and the existing PSGallery GUID `66b95cf8-97e8-4448-8015-38d0e35456a0`. Publishing under the same name with a different GUID would break `Update-Module` and module identity.
- Follow the ModuleForge conventions: one function per file with PascalCase approved verbs, `begin`/`process` blocks, help with examples, and no nested functions.

## Non-goals (for now)

- **Audio.** Microphones are hard to get right, and recording system sound needs WASAPI loopback, which ffmpeg doesn't provide. The escape hatches (`-FFmpegInputArgument`, `-FFmpegOutputArgument`) let advanced users add it themselves.
- **Linux Wayland.** As of late 2026, ffmpeg has no released PipeWire grabber; the pipewiregrab patch series (trac #10742) is not merged. Check `XDG_SESSION_TYPE` and fail with a clear message.
- **Rendering terminal text to video** when there is no screen (asciinema/VHS territory).
- **H.266/VVC as a named codec.** `libvvenc` is too slow to record with and few players support it. People who want it can pass it with `-VideoCodec`.
- **A general ffmpeg wrapper.** The media commands cover the path from a recording to something you can share, and nothing more.

---

## Command set

| Command | Status | Purpose |
| --- | --- | --- |
| `Find-FFmpeg` | Phase 1 | Finds ffmpeg and ffprobe: the `-Path` parameter, then `$env:PSSCREENRECORDER_FFMPEG`, then `PATH`. Never installs. Throws with install suggestions for the current OS. The result is cached for the session. `-IncludeCapability` adds the capture sources and the encoders that passed a test encode. |
| `Get-VideoMetadata` | Phase 1 | ffprobe JSON as a typed object: duration as a `TimeSpan`, width, height, frame rate, codec, bitrate, size. Named so it doesn't clash with the `Get-MediaInfo` module. |
| `ConvertTo-Gif` | Phase 1 | One-pass palette (`split`, then `palettegen`, then `paletteuse`). Options: `-Fps`, `-Width`, `-Start`, `-End`, `-Dither`, `-Loop`, `-RemoveDuplicateFrames` (`mpdecimate`), `-Force`. Pipeline input by `FullName`. Alias `convert-mp4togif`. Later: `-MaxSize`. |
| `Start-ScreenRecording` | Phase 2 | Returns a session object. Targets: `-Monitor`, `-Window`, `-CurrentTerminal`, `-Rectangle`, or a region from the pipeline. Start and stop: `-Delay`, `-Duration`, `-StartOnFocusLoss`, `-StopOnFocusReturn`, and `-Wait`. Options: `-Quality Lossless\|High\|Standard`, `-Codec H264\|HEVC\|AV1`, `-Encoder Auto\|Software\|Nvenc\|Qsv\|Amf\|MediaFoundation\|VideoToolbox`. |
| `Stop-ScreenRecording` | Phase 2 | Sends `q` to ffmpeg's stdin, waits, remuxes the `.mkv` to `.mp4` with `+faststart`, and returns the file and its metadata. |
| `Get-ScreenRecording` | Phase 2 | Running sessions: elapsed time, frames, dropped frames (from `-progress`). |
| `Get-CaptureTarget` | Phase 2/3 | Lists monitors and windows with their bounds in physical pixels. |
| `Select-ScreenRegion` | Phase 3 | Drag-to-select overlay that outputs a rectangle, so `Select-ScreenRegion \| Start-ScreenRecording` works. |
| `Invoke-ScreenRecording` | Phase 3 | `-ScriptBlock { ... }` records the current terminal while the script block runs. Gives repeatable README demos. |
| `Compress-Video` | Phase 3 | Replaces `start-psMp4Optimize` from 1.0.14: re-encodes a lossless recording to something smaller. `-Codec`, `-MaxSize`. |
| `ConvertTo-WebP` | Phase 3 | Animated WebP, which is much smaller than GIF and renders on GitHub. The name clashes only with `PSImageConverter`; recheck before release. |
| `Edit-Video` | Phase 3 | `-Start`, `-End`, `-Crop`, `-Speed`. |
| `Export-VideoFrame` | Phase 3 | Saves a PNG frame for a thumbnail or docs. |
| `Get-` / `Set-ScreenRecorderConfig` | Phase 3 | Saved defaults (ffmpeg path, output folder, codec, encoder), stored under `[Environment]::GetFolderPath('ApplicationData')`. |

Names were checked against PSGallery in November 2026. `ConvertTo-Gif` also exists in `CaptureIT`, a small module, and we keep the name anyway.

---

## Architecture

- **Every native call goes through one place.**
  - `Invoke-FFmpeg` (private) runs ffmpeg or ffprobe to completion. It takes arguments as an **array**, never one string, so paths with spaces just work. It collects stdout and stderr, throws with the tail of stderr on a non-zero exit, and can parse `-progress pipe:1` for `Write-Progress`.
  - `Start-FFmpegProcess` (private, Phase 2) handles long recordings. It uses `System.Diagnostics.Process` with stdin redirected, so stopping cleanly is a matter of writing `q`. This replaces the 2022 `WScript.Shell.SendKeys('q')` approach: if focus moved, that sent `q` to whatever window had it.
  - Callers mock these two functions. Almost everything else becomes pure argument building that can be unit tested.
- **Capture backends.** One builder per backend turns a capture target (kind, physical X/Y/width/height, monitor index, window handle or exe name) into ffmpeg input arguments:

  | Backend | Platform | Notes |
  |---|---|---|
  | `gfxcapture` | Windows, ffmpeg 8.1+ | Windows.Graphics.Capture. Captures a window even when it's covered. Takes `hwnd`, `hmonitor`, `monitor_idx`, `window_exe`/`window_title` (regex) and `crop_*`. No yellow border by default. Outputs D3D11 frames: use `hwdownload,format=bgra` for software encoders, or pass them straight to NVENC/QSV/AMF. |
  | `ddagrab` | Windows, ffmpeg 6+ | Desktop Duplication. `output_idx` plus `offset_x`/`offset_y`/`video_size`. Offsets are relative to the monitor. Also outputs D3D11 frames. |
  | `gdigrab` | Windows, any version | Fallback. Coordinates are physical pixels on the virtual desktop. `title=` for windows. |
  | `avfoundation` | macOS | Takes `"<screen>:none"` and records the whole screen, then `crop` cuts out the region. Has `-capture_cursor` and `-capture_mouse_clicks`. Needs Screen Recording permission for the terminal. Retina displays mean converting points to pixels. |
  | `x11grab` | Linux X11 | `-i :0.0+X,Y`, `-draw_mouse`. Works with Xvfb on headless machines. |
  | `synthetic` | Any (hidden) | `-f lavfi -i testsrc2=size=WxH:rate=N`. Lets the whole recording lifecycle run in CI with no display. |

  Pick backends by detected capability (`ffmpeg -filters` / `-devices`), not by ffmpeg version. The minimum is about ffmpeg 6.0, because Ubuntu 24.04's apt package is around 6.1 and Debian 13's around 7.1.
- **DPI and scaling (Windows).** pwsh is DPI-unaware: `GetThreadDpiAwarenessContext` reports 0, so it gets virtualised coordinates. Every 1.x fix multiplied by one global scale factor (`DESKTOPVERTRES / VERTRES`), which only describes the primary monitor and can't work with mixed DPI. The fix:
  1. Wrap region and cursor code in `SetThreadDpiAwarenessContext(PER_MONITOR_AWARE_V2 = -4)`, which applies to the thread, not the host process.
  2. Use `GetCursorPos`, `MonitorFromPoint`/`GetMonitorInfo` and `DwmGetWindowAttribute(EXTENDED_FRAME_BOUNDS)`. These then return physical pixels, so no scale maths is needed.
  3. For whole windows and monitors, `gfxcapture` by `hwnd`/`hmonitor` avoids coordinates altogether.
  4. Tested working on pwsh 7.6, but only on a single 100% monitor. **Mixed-DPI testing needs a real rig.**
- **Current terminal.** `GetForegroundWindow()` at the moment the command runs. Without P/Invoke (for example under CLM), walk `(Get-Process -Id $PID).Parent` up to the terminal (WindowsTerminal, Code, and so on) and pass `window_exe` to `gfxcapture`.
  - The 1.x code looked for `Get-Process *powershell*` with a `MainWindowHandle`. Under Windows Terminal or VS Code no pwsh process has one, so the handle was `$null` and recording never stopped.
- **Recordings survive a crash.** Record to `.mkv`, then on stop remux to `.mp4` (`-c copy -movflags +faststart`), which is instant. An MP4 whose ffmpeg was killed has no index and won't play.
- **No orphaned ffmpeg.** Register a `PowerShell.Exiting` handler that stops running sessions, and store PIDs so `Stop-ScreenRecording` works from a new session.
- **Quality presets.**
  - `Lossless`: `libx264rgb -crf 0 -preset ultrafast`, or `hevc_nvenc` lossless, in `.mkv`. This was the 2022 approach; text stays crisp and GIFs come out best. Most players can't play RGB H.264, so `Compress-Video` or `ConvertTo-*` comes next.
  - `High` and `Standard`: hardware encoders where available, `yuv420p` for compatibility.
- **Encoder selection.** Appearing in `ffmpeg -encoders` doesn't mean an encoder works. On the RTX 3090 dev machine, `av1_nvenc` is listed but fails, because Ampere can't encode AV1. So run a one-frame test encode per encoder and cache it per session.
- **Codecs.**
  - **H.264:** the default. Plays everywhere and renders on GitHub.
  - **HEVC:** an option. Needs `-tag:v hvc1` in MP4 for Apple players, and Windows needs the HEVC extension to play it.
  - **AV1:** an option, with good browser support.
  - **VVC:** only through `-VideoCodec`.
- **Windows the module draws (overlay, border, countdown).** Set `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` so they don't appear in the recording. Check this per backend.
- **CLM.** The `clm` rule set reports around 45 advisory findings, mostly `[PSCustomObject]@{}`, generic lists, `[Environment]`, `[math]` and the `ToTimeSpan` class. We accept these. Where CLM is enforced, the supported route is signing the module so the WDAC policy trusts it, which runs it in FullLanguage. Win32 calls live in one private helper. Under CLM, a reduced mode still offers monitor capture, `window_exe`/`window_title` capture and all the media commands. ffmpeg is an external exe, so WDAC governs it, not CLM. The CLM analyzer rules are advisory.
- **Output objects.** Return `FileInfo` with metadata attached, so results pipe into `ConvertTo-Gif`. Default output goes to `[Environment]::GetFolderPath('MyVideos')` with timestamped names. Use `ShouldProcess` and `-Force` instead of overwrite prompts.

## Crescendo: decided against

Crescendo suits call-it-and-parse-the-result tools. Three things count against it here:

- Our hard parts are a long-running process (start, keep a handle, write `q` to stdin, clean up on exit), building filter graphs and choosing encoders.
- It generates a module at build time, which clashes with ModuleForge's one-function-per-file build.
- Its last release was 1.1.0 in September 2023.

ffmpeg's output is already structured enough: `-progress pipe:1` (key=value), `ffprobe -of json` and `-loglevel error`.

---

## FFmpeg and licensing

psScreenRecorder never downloads, installs or bundles ffmpeg:

- ffmpeg builds are LGPL or GPL depending on how they were configured. Common Windows builds (gyan.dev, BtbN) are GPLv3.
- Builds often include patent-encumbered encoders (x264, x265).
- Redistributing them carries obligations this project doesn't take on.

`Find-FFmpeg` finds ffmpeg and, if it's missing, explains how to install it:

- Windows: `winget install Gyan.FFmpeg`
- macOS: `brew install ffmpeg`
- Linux: `sudo apt install ffmpeg`, or the distro's equivalent

The readme says the same.

## Headless machines and ARM

- **Headless machines.** Without a display there's nothing to capture, and the module should say so clearly.
  - Linux can use Xvfb (`xvfb-run`) with `x11grab`.
  - On Windows, services, locked sessions and disconnected RDP sessions have no rendered desktop.
  - GitHub's `windows-latest` runners do have an interactive session. `gdigrab` probably works there; `ddagrab`/`gfxcapture` on the basic display adapter haven't been tested.
  - Media commands and the synthetic backend work anywhere.
- **ARM64.**
  - pwsh and P/Invoke work the same on ARM64.
  - Windows on ARM: D3D11 capture works, and hardware encoding goes through `h264_mf` (Media Foundation), which doesn't depend on the GPU vendor.
  - macOS: `h264_videotoolbox`.
  - Linux ARM64: `x11grab`.
  - GitHub has `ubuntu-24.04-arm`, `windows-11-arm` and `macos-latest` (ARM) runners.

## Testing strategy

1. **Unit tests** (`*.Tests.ps1` next to each function, any OS) cover argument builders, rectangle normalisation and even dimensions, region-to-monitor mapping, filter-graph strings, encoder selection and ffmpeg discovery. `Invoke-FFmpeg` and `Start-FFmpegProcess` are mocked.
2. **Integration tests** (`tests/`, need ffmpeg, skipped if it's missing) make clips with `testsrc2`, run them through the commands, and check the results with ffprobe: duration, size, codec, frame count, and that a killed recording can still be read.
3. **Windows capture smoke tests** are marked `-Skip:(-not $IsWindows)`. Mixed-DPI correctness is a manual checklist.

CI runs the main Ubuntu job (with coverage and the PR comment) plus a matrix of Windows, macOS and ARM runners. Every runner installs ffmpeg so the integration tests run.

---

## Phases

### Phase 1: foundation (all testable headless)

- [x] Restore the PSGallery GUID in `moduleForgeConfig.xml`; add tags and an icon URL
- [x] Delete the Bartender leftovers: `btConfig.xml`, `.bt*` files, `rev/`, `documentation/`, the old build output, `postBuildScripts/`, and the unused `source` folders
- [x] Tag `v1.0.8` on `c66d3a1` so ModuleForge's next version follows on (**still to push**: `git push origin v1.0.8`)
- [x] This roadmap
- [x] `Invoke-FFmpeg` (private)
- [x] `Find-FFmpeg`
- [x] `Get-VideoMetadata`
- [x] `ConvertTo-Gif` (+ `convert-mp4togif` alias)
- [x] Unit tests, plus the integration suite on `testsrc2`
- [x] CI: install ffmpeg; turn on the multi-OS and ARM matrix
- [x] Rewrite the readme in UTF-8, with the licensing statement

### Phase 2: recording core

- [ ] Capture-target model, plus `Get-CaptureTarget` (monitors first)
- [ ] Argument builders for each backend (gfxcapture, ddagrab, gdigrab, avfoundation, x11grab, synthetic)
- [ ] Encoder capability detection with test encodes and a cache
- [ ] `Start-FFmpegProcess`, `Start-`/`Stop-`/`Get-ScreenRecording`, with `.mkv` then remux to `.mp4`
- [ ] `-Delay`, `-Duration`, `-Wait`; clean-up on `PowerShell.Exiting`
- [ ] Windows: DPI-aware helper for monitors, windows and the cursor; `-CurrentTerminal`
- [ ] Focus modes: `-StartOnFocusLoss` / `-StopOnFocusReturn` (Windows first)

### Phase 3: polish

- [ ] `Select-ScreenRegion` overlay (WinForms/WPF; pwsh 7.6 is STA), excluded from capture
- [ ] `Invoke-ScreenRecording -ScriptBlock`
- [ ] `Compress-Video`, `ConvertTo-WebP`, `Edit-Video`, `Export-VideoFrame`, `ConvertTo-Gif -MaxSize`
- [ ] `Get-`/`Set-ScreenRecorderConfig`
- [ ] A stop hotkey (`RegisterHotKey`)
- [ ] Click highlighting (native on macOS; an overlay on Windows)
- [ ] Focus modes for macOS (`osascript`) and X11 (`xdotool`)
- [ ] Replace `hw.gif` with a demo made by v2 itself

### Open items

- [ ] Push the `v1.0.8` tag and `main`; make `main` the default branch and archive `master`
- [ ] Add a LICENSE file (none exists; `licenseUri` is empty in `moduleForgeConfig.xml`)
- [ ] Turn on `psgalleryRelease.yml` when v2 is ready (needs the `PSGALLERY` secret)
- [ ] Test on a mixed-DPI rig
- [ ] Check `ddagrab`/`gfxcapture` on GitHub Windows runners

---

## History

| Version | Date | Notes |
| --- | --- | --- |
| 1.0.1 | 2019-03 | `new-psScreenRecord` with a PowerShell loop that saves a JPEG per frame and stitches them with ffmpeg. Start and stop follow which window has focus. Based on a 2017 script. |
| 1.0.2 | 2019-03 | Added `convert-mp4togif` (5 fps, 320 px) and `install-ffMpeg` (zeranoe.com, which shut down in 2020). |
| 1.0.6 | 2019-03 | First scaling fix: one global scale factor. The cursor wasn't scaled. |
| 1.0.7 | 2019-03 | Second scaling fix: cursor scaled too (reported by lazytao). |
| 1.0.8 | 2019-06 | `-Force`, `-captureCursor`, output to Documents. GIF gained `-fps` and `-scale`. **Last published version.** |
| 1.0.9–1.0.14 | 2022-08 | Never published, recovered from a backup. Native `gdigrab` capture, ffmpeg from `PATH` ("leave the install to user"), focus handle taken with `GetForegroundWindow()`, stop by `SendKeys('q')`. Scaling left in the "too hard basket". Lossless `libx264rgb` capture plus `start-psMp4Optimize` (x265 CRF 28). |

Problems that stopped 1.x from working on modern Windows and pwsh 7:

- `get-screenScaling` compiled against `System.Drawing.dll`. On .NET, `Graphics` moved to `System.Drawing.Common`, so `Add-Type` fails with CS1069.
- The focus detection described under [Architecture](#architecture).
- Paths weren't quoted in ffmpeg argument strings.
- Frame-rate drift from the screenshot loop.

## Dev machine notes (November 2026)

- Windows 11 Pro, pwsh 7.6.10 (STA), ffmpeg 9.1 full build (gyan.dev) in `C:\Users\adria\Documents\Path`, RTX 3090.
- Capture sources that work: `gdigrab`, `ddagrab`, `gfxcapture` (monitor and `window_exe`), and zero-copy `gfxcapture`/`ddagrab` to `h264_nvenc`.
- Encoders that work: `libx264`, `libx265`, `libsvtav1`, `libvvenc`, `h264_nvenc`, `hevc_nvenc`, `h264_mf`. Fail: `av1_nvenc`, QSV, AMF.
- The build includes `whisper` (audio transcription). Interesting, but out of scope while audio is.
