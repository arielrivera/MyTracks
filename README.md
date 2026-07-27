# ArielSplitter

A native macOS application for AI-powered musical source separation. Split a song into independent stems (vocals, drums, bass, guitar, piano, other) using the open-source [Demucs](https://github.com/facebookresearch/demucs) model, all processed locally on your Mac.

## Features

- Drag-and-drop or open any audio/video file supported by `AVFoundation`.
- Choose which stems to extract.
- Select an output folder.
- Real-time progress with status messages.
- Built-in mixer to preview stems after separation.
- Export individual WAV files.
- Native SwiftUI interface, no Electron or web wrapper.

## Requirements

- Apple Silicon Mac (M1 or newer) — currently tested only on M1 Macs
- macOS 14 (Sonoma) or later
- Xcode 15+ or Swift 5.9 toolchain
- Python 3.10+ with `demucs`, `torch`, and `torchaudio` installed
- An internet connection the first time Demucs downloads a model (after that, processing is fully local)

## Install Python dependencies

```bash
python3 -m pip install demucs torch torchaudio
```

## Build and run

Open `Ariel's Splitter` in Xcode or run from the terminal:

```bash
cd "Ariel's Splitter"
swift build
swift run ArielSplitter
```

Or run the built executable directly:

```bash
.build/debug/ArielSplitter
```

## Quick test

Place a test audio/video file at:

```text
~/Downloads/samplesong.x
```

Then launch the app and choose **Debug → Run Auto Test** (or press `Cmd + Option + T`).

> Replace `samplesong.x` with any supported audio or video file.

## Project structure

```text
Ariel's Splitter/
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

## AI prompts

The original AI prompts used to generate this app from scratch are included in the `prompts/` folder, in both Spanish and English, for macOS and Windows. They are completely optional — the app is already built and ready to use.

## License

See the `prompts/` folder for licensing notes on third-party models and dependencies.
