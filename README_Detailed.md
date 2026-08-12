# ArielSplitter — Detailed Documentation

## Overview

ArielSplitter is a native macOS desktop application that separates a musical mix into independent audio stems using the [Demucs](https://github.com/facebookresearch/demucs) source-separation model. The entire pipeline runs locally: the Swift/SwiftUI front end coordinates a Python backend that loads the model, performs inference, and writes WAV files.

## Technologies used

### macOS front end

- **Swift 5.9** with the Swift Package Manager
- **SwiftUI** for the user interface
- **AppKit** for file dialogs, drag-and-drop, and menu commands
- **AVFoundation / AVAudioEngine** for audio playback and mixing
- **Foundation** for process management and file I/O
- **os.log** for structured logging

### AI separation backend

- **Python 3.10+**
- **Demucs** (Facebook Research) — pre-trained music source separation
- **PyTorch / torchaudio** — model runtime and audio I/O
- **FFmpeg** (pulled in by Demucs/torchaudio) — audio decoding

### Build tools

- `swift-tools-version: 5.9`
- **Command Line Tools are sufficient** (`xcode-select --install`). Full Xcode is
  only needed for SwiftUI `#Preview`, which is compiled out under SwiftPM via
  `#if !SWIFT_PACKAGE` because the backing macro plugin ships with Xcode only.

### Command-line tools

The app shells out to two external binaries:

| Tool | Required? | Used for |
| --- | --- | --- |
| `ffmpeg` | **Yes** | Decoding formats libsndfile cannot read (`.m4a`, `.mp4`, AAC) |
| `yt-dlp` | No | The "Download from URL" panel only |

Both are located by probing `/opt/homebrew/bin`, `/usr/local/bin`,
`~/.local/bin` and `/opt/local/bin` directly, because a GUI-launched app
inherits a minimal `PATH` that excludes Homebrew.

## System requirements

- Apple Silicon Mac (M1 or newer) — currently tested only on M1 Macs
- macOS 14 Sonoma or later
- At least 8 GB RAM (16 GB recommended for long tracks)
- Several GB of free disk space. Budget roughly **270 MB per 6-stem run**
  (stems are uncompressed WAV, ~45 MB each) plus ~500 MB of Demucs model cache
  in `~/.cache/huggingface`.

## Installation

### Automatic (recommended)

```bash
cd MyTracks
./setup.sh
```

The script is idempotent and does the following, reporting a clear verdict:

1. Confirms a Swift toolchain is present.
2. Creates `venv/` at the repository root if missing.
3. Installs `requirements.txt` into it.
4. Verifies every module `separate.py` imports actually resolves.
5. Checks for `ffmpeg` (blocking) and `yt-dlp` (optional).
6. Runs `swift build`.

Flags: `--install-tools` also installs missing tools via Homebrew;
`--recreate` rebuilds the virtualenv from scratch.

### Manual

#### 1. Create a virtualenv at the repository root

```bash
cd MyTracks
python3 -m venv venv
./venv/bin/python3 -m pip install -r requirements.txt
```

The location matters. `PythonLocator` searches for `venv/`, `.venv/` or `env/`
while walking up from `separate.py`, and probes each candidate for the required
modules using `importlib.util.find_spec`. The first interpreter with all of them
wins. A global `pip install` is unreliable here: a GUI app resolves
`/usr/bin/env python3` against a minimal `PATH`, which typically finds a bare
system interpreter with no `numpy`.

#### 2. Install the command-line tools

```bash
brew install ffmpeg    # required
brew install yt-dlp    # optional
```

#### 3. Verify

```bash
./venv/bin/python3 -c "import demucs, torch, torchaudio, numpy, soundfile, librosa; print('OK')"
```

#### 4. Build the Swift package

```bash
cd "Ariel's Splitter"
swift build
```

To build a release binary:

```bash
swift build -c release
```

## Running the app

### From the terminal

```bash
swift run ArielSplitter
```

Or, after building:

```bash
.build/debug/ArielSplitter
```

### From Xcode

Open the `Ariel's Splitter` folder in Xcode and press `Cmd + R`.

## How to use the app

1. **Open a file**  
   Drag an audio/video file onto the window, or choose **File → Open Audio File…** (`Cmd + O`).

2. **Select stems**  
   Toggle the stems you want to extract (vocals, drums, bass, guitar, piano, other).

3. **Choose output folder**  
   Pick or create a directory where the WAV stems will be saved.

4. **Start separation**  
   Click the separate button. The app launches the Python backend and streams progress back to the UI.

5. **Preview and export**  
   After separation, use the mixer to solo/mute/preview stems, then export the final files.

## Command-line usage

The Swift app is the intended interface, but the underlying Python wrapper can be invoked directly for testing or automation:

```bash
python3 "Ariel's Splitter/Sources/ArielSplitter/Resources/separate.py" separate \
  /path/to/input.mp3 \
  /path/to/output_folder \
  '["vocals","drums","bass","other"]' \
  htdemucs
```

Arguments:

1. `separate` — operation mode
2. Input audio/video file path
3. Output directory path
4. JSON array of desired stems
5. Model name: `htdemucs` (4 stems) or `htdemucs_6s` (6 stems)

The script prints machine-readable lines to stdout:

- `DEVICE: ...`
- `STATUS: ...`
- `PROGRESS: 0.42`
- `FILE: /path/to/vocals.wav`
- `ERROR: ...`
- `DONE`

## Project structure

```text
ArielSplitter/
├── Package.swift
├── README.md
├── README_Detailed.md
├── prompts/                # Original AI prompts (optional)
├── Sources/
│   └── ArielSplitter/
│       ├── App/              # App entry point and design system
│       ├── Audio/            # AVAudioEngine playback
│       ├── Download/         # yt-dlp integration, tool discovery, updates
│       ├── Models/           # Data models
│       ├── Resources/        # separate.py (Demucs wrapper)
│       ├── Separation/       # SeparationEngine, PythonLocator
│       ├── ViewModels/       # AppViewModel
│       └── Views/            # SwiftUI views
```

Repository-level files sit one directory above the Swift package:

```text
MyTracks/
├── setup.sh             # One-command environment setup
├── requirements.txt     # Python dependencies
├── venv/                # Created by setup.sh (git-ignored)
└── Ariel's Splitter/    # The Swift package shown above
```

## Architecture

### Swift layers

| Layer | Responsibility |
|-------|--------------|
| `ArielSplitterApp.swift` | App entry point, window config, menu commands |
| `AppViewModel.swift` | Central state, coordinates UI, engine, and audio manager |
| `SeparationEngine.swift` | Spawns Python process, parses stdout, reports progress |
| `PythonLocator.swift` | Finds an interpreter that actually has the required modules |
| `MediaDownloader.swift` | Drives `yt-dlp`, parses progress, resolves output paths |
| `MediaToolLocator.swift` | Locates external binaries despite a GUI app's minimal `PATH` |
| `ToolUpdater.swift` | Updates `yt-dlp` via whichever installer owns it |
| `AudioEngineManager.swift` | Loads stems into `AVAudioEngine`, playback, mixing |
| `Views/` | SwiftUI views for each screen section |
| `Models/` | `AudioFileInfo`, `StemTrack`, `StemCategory`, `SeparationState`, `DownloadState` |
| `DesignSystem.swift` | Shared colors, fonts, and UI constants |

### Python wrapper

`Resources/separate.py` handles:

- Loading the Demucs model
- Reading the input file with FFmpeg/torchaudio
- Running inference
- Writing one WAV file per requested stem
- Streaming progress and file paths back to Swift

## Model selection

The app automatically picks the model based on the selected stems:

- `htdemucs` — used for the classic 4-stem separation: vocals, drums, bass, other
- `htdemucs_6s` — used when guitar, piano, or other instruments are requested

## Auto test

A built-in debug menu item loads a hard-coded test file and starts separation automatically:

- Menu: **Debug → Run Auto Test**
- Shortcut: `Cmd + Option + T`
- Expected test file: `~/Downloads/samplesong.x`

Replace `samplesong.x` with any supported audio or video file. This is intended for development and CI smoke tests.

## Output files

Each separation run produces one 44.1 kHz stereo WAV file per selected stem in the chosen output folder:

```text
output_folder/
├── vocals.wav
├── drums.wav
├── bass.wav
├── guitar.wav
├── piano.wav
└── other.wav
```

## Troubleshooting

### “Python script not found”

Make sure you are running the app from a path where `Sources/ArielSplitter/Resources/separate.py` is reachable, or that the script is bundled in the built app.

### Demucs model download fails

The first run downloads the model weights. Ensure you have a working internet connection and enough disk space.

### Silent output files

Check that the input file is not DRM-protected and that FFmpeg can decode it.

### `ModuleNotFoundError: No module named 'numpy'`

The app found a Python interpreter, but not the one holding your packages. This
is almost always a global `pip install` combined with a GUI launch: the app
resolves against a minimal `PATH` and lands on a bare system interpreter.

Create a virtualenv at the repository root and install into it — see
[Installation](#installation). Since `PythonLocator` probes candidates for the
required modules, an interpreter missing them is now rejected outright, and the
error names exactly which modules are absent along with the `pip install` line
to fix it.

### `LibsndfileError: Format not recognised`

The input is in a format libsndfile cannot decode — most commonly `.m4a`/AAC or
`.mp4`. `librosa` 1.0 removed the `audioread` fallback, so libsndfile is its only
backend (WAV, MP3, FLAC, OGG, AIFF).

`separate.py` handles this by transcoding to a temporary WAV with ffmpeg, so this
error in practice means **ffmpeg is not installed or was not found**. Install it
with `brew install ffmpeg` and re-run `./setup.sh` to confirm it is detected.

### Edits to `separate.py` appear to do nothing

`SeparationEngine` prefers the copy in `Bundle.main` over the one in the source
tree, and SwiftPM only refreshes that copy at build time. **Run `swift build`
after every change to `separate.py`**, or you will silently keep running the old
version.

### `Invalid manifest` / undefined `PackageDescription` symbols

`swift build` fails while compiling `Package.swift` itself, with linker errors
about missing `PackageDescription.Package` initializers. This indicates a broken
Command Line Tools installation, not a problem with the manifest. Reinstall:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
sudo xcode-select --install
```

### yt-dlp downloads fail after working previously

Sites change their players and break extraction regularly; the fix is a newer
yt-dlp. The app detects the common signatures and offers an **Update yt-dlp**
button on the failure itself.

Note that `yt-dlp -U` **cannot** update a Homebrew install — Homebrew ships it as
a Python wheel, and `-U` refuses with *"you installed yt-dlp with pip..."*. The
app routes the update to the owning package manager (`brew upgrade yt-dlp`,
`pip install --upgrade yt-dlp`, or genuine `-U` for a standalone binary). `-U` is
still used as a read-only version check.

## Distribution notes

Xcode (or the Swift toolchain) is only required to **build** the app from source. A future packaged release — a signed `.app` bundle — would not require end users to install Xcode or the Swift toolchain. To produce such a release you would need to:

1. Build a release binary (`swift build -c release` or archive via Xcode).
2. Wrap it in a macOS `.app` bundle.
3. Sign and notarize it with an Apple Developer account so Gatekeeper allows it on other Macs.

Embedding or bundling the Python runtime and Demucs/PyTorch dependencies is the remaining packaging challenge; without that, the packaged app would still need the user to have a compatible Python environment.

## Development notes

- The project uses `StrictConcurrency` as an experimental feature in debug builds.
- The app is a single-window SwiftUI app with a fixed minimum size.
- All heavy work (separation, file I/O) runs off the main thread; UI updates are dispatched to `@MainActor`.

## AI prompts

The original AI prompts used to generate this app from scratch are included in the `prompts/` folder, in both Spanish and English, for macOS and Windows. They are completely optional — the app is already built and ready to use.

## License and attribution

ArielSplitter is a personal/educational project. The Demucs model and PyTorch stack are subject to their own licenses. See the files in the `prompts/` folder for the original build prompts and licensing guidance.
