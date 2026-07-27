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
- Xcode 15+ or the standalone Swift toolchain

## System requirements

- Apple Silicon Mac (M1 or newer) — currently tested only on M1 Macs
- macOS 14 Sonoma or later
- At least 8 GB RAM (16 GB recommended for long tracks)
- Several GB of free disk space for model cache and output WAV files

## Installation

### 1. Clone or open the project

```bash
cd "Ariel's Splitter"
```

### 2. Install Python dependencies

The separation engine needs a working Python 3 environment with Demucs and PyTorch:

```bash
python3 -m pip install demucs torch torchaudio
```

Verify the install:

```bash
python3 -c "import demucs; import torch; import torchaudio; print('OK')"
```

### 3. Build the Swift package

```bash
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
│       ├── Models/           # Data models
│       ├── Resources/        # separate.py (Demucs wrapper)
│       ├── Separation/       # SeparationEngine
│       ├── ViewModels/       # AppViewModel
│       └── Views/            # SwiftUI views
```

## Architecture

### Swift layers

| Layer | Responsibility |
|-------|--------------|
| `ArielSplitterApp.swift` | App entry point, window config, menu commands |
| `AppViewModel.swift` | Central state, coordinates UI, engine, and audio manager |
| `SeparationEngine.swift` | Spawns Python process, parses stdout, reports progress |
| `AudioEngineManager.swift` | Loads stems into `AVAudioEngine`, playback, mixing |
| `Views/` | SwiftUI views for each screen section |
| `Models/` | `AudioFileInfo`, `StemTrack`, `StemCategory`, `SeparationState` |
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

## Development notes

- The project uses `StrictConcurrency` as an experimental feature in debug builds.
- The app is a single-window SwiftUI app with a fixed minimum size.
- All heavy work (separation, file I/O) runs off the main thread; UI updates are dispatched to `@MainActor`.

## AI prompts

The original AI prompts used to generate this app from scratch are included in the `prompts/` folder, in both Spanish and English, for macOS and Windows. They are completely optional — the app is already built and ready to use.

## License and attribution

ArielSplitter is a personal/educational project. The Demucs model and PyTorch stack are subject to their own licenses. See the files in the `prompts/` folder for the original build prompts and licensing guidance.
