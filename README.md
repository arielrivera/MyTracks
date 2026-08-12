# ArielSplitter

A native macOS application for AI-powered musical source separation. Split a song into independent stems (vocals, drums, bass, guitar, piano, other) using the open-source [Demucs](https://github.com/facebookresearch/demucs) model, all processed locally on your Mac.

## Features

- One drop zone for everything: drop a file, drop a link, paste a URL, or click to browse.
- Download audio, video, or both from a URL with `yt-dlp` — the audio loads for separation automatically.
- Choose which stems to extract.
- Real-time progress with status messages; the window shows only what applies to the current stage.
- Built-in mixer to solo, mute, and set levels after separation.
- Export the current mix or individual stems, without overwriting earlier exports.
- Write stems and exports as WAV, FLAC, ALAC, MP3, or AAC — separation always runs at full quality.
- Output files are named after the source track, so separate runs don't overwrite each other.
- Consolidated settings (`⌘,`), including yt-dlp updates and environment diagnostics.
- Native SwiftUI interface, no Electron or web wrapper.

## Requirements

- Apple Silicon Mac (M1 or newer) — currently tested only on M1 Macs
- macOS 14 (Sonoma) or later
- **Command Line Tools** (`xcode-select --install`) — full Xcode is *not* required
- Python 3.10+
- **ffmpeg** — required, not optional (see below)
- **yt-dlp** — optional, only for downloading media from a URL
- An internet connection the first time Demucs downloads a model (after that, processing is fully local)

> **Why ffmpeg is required:** `librosa` 1.0 dropped its `audioread` fallback, so it
> can only open formats libsndfile understands — WAV, MP3, FLAC, OGG, AIFF. Anything
> else, including the `.m4a`/`.mp4` files that URL downloads produce, is transcoded
> with ffmpeg first. Without it those files fail to load.

## Quick start

```bash
git clone <this repo>
cd MyTracks
./setup.sh
```

`setup.sh` creates a virtualenv at the repository root, installs everything in
`requirements.txt`, checks for ffmpeg and yt-dlp, builds the Swift package, and
tells you exactly what is missing if anything is. It is safe to re-run.

```bash
./setup.sh --install-tools   # also install missing ffmpeg/yt-dlp via Homebrew
./setup.sh --recreate        # rebuild the virtualenv from scratch
```

Then run the app:

```bash
cd "Ariel's Splitter"
swift run ArielSplitter
```

Or run the built executable directly:

```bash
.build/debug/ArielSplitter
```

### Manual setup

If you would rather not use the script:

```bash
python3 -m venv venv
./venv/bin/python3 -m pip install -r requirements.txt
brew install ffmpeg yt-dlp
cd "Ariel's Splitter" && swift build
```

> **Use a virtualenv at the repository root.** The app searches for `venv/`,
> `.venv/` or `env/` near the project and rejects any interpreter missing a
> required module. A global `pip install` is not reliably picked up, because a
> GUI-launched app does not inherit your shell's `PATH`.

## Quick test

Place a test audio/video file at:

```text
~/Downloads/samplesong.x
```

Then launch the app and choose **Debug → Run Auto Test** (or press `Cmd + Option + T`).

> Replace `samplesong.x` with any supported audio or video file.

## Project structure

```text
MyTracks/
├── setup.sh                    # One-command environment setup
├── requirements.txt            # Python dependencies
├── README.md
├── README_Detailed.md
├── prompts/                    # Original AI prompts (optional)
├── venv/                       # Created by setup.sh (git-ignored)
└── Ariel's Splitter/
    ├── Package.swift
    └── Sources/
        └── ArielSplitter/
            ├── App/            # App entry point and design system
            ├── Audio/          # AVAudioEngine playback
            ├── Download/       # yt-dlp integration and tool discovery
            ├── Models/         # Data models, URL validation
            ├── Resources/      # separate.py (Demucs wrapper)
            ├── Separation/     # SeparationEngine, PythonLocator
            ├── ViewModels/     # AppViewModel
            └── Views/          # SwiftUI views, Settings and Export dialogs
```

## AI prompts

The original AI prompts used to generate this app from scratch are included in the `prompts/` folder, in both Spanish and English, for macOS and Windows. They are completely optional — the app is already built and ready to use.

## License

See the `prompts/` folder for licensing notes on third-party models and dependencies.
