#!/usr/bin/env bash
#
# One-command setup for ArielSplitter on Apple Silicon macOS.
#
# Creates a Python virtualenv, installs the separation dependencies, checks
# (and optionally installs) the command-line tools the app shells out to,
# builds the Swift package, and writes a double-clickable launcher. Safe to
# re-run: an existing virtualenv is reused unless --recreate is passed.
#
#   ./setup.sh                 set up; offer to install anything missing
#   ./setup.sh --install-tools install Homebrew/Python/ffmpeg/yt-dlp as needed
#   ./setup.sh --recreate      delete and rebuild the virtualenv first
#   ./setup.sh --release       build the optimized binary (used by ./run.sh)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_ROOT/venv"
PACKAGE_DIR="$REPO_ROOT/Ariel's Splitter"
APP_BUNDLE="$REPO_ROOT/ArielSplitter.app"

# Homebrew and common user prefixes are invisible in some environments
# (GUI launches, fresh Terminal tabs before the profile loads).
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${PATH}"

INSTALL_TOOLS=0
ASSUME_NO=0
RECREATE=0
RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --install-tools|-y|--yes) INSTALL_TOOLS=1 ;;
        --no-install-tools)       ASSUME_NO=1 ;;
        --recreate)               RECREATE=1 ;;
        --release)                RELEASE=1 ;;
        -h|--help)
            sed -n '3,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

# Colour, unless the terminal or NO_COLOR says otherwise.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; RED=""; GREEN=""; YELLOW=""; DIM=""; RESET=""
fi

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$1"; }
step() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }
note() { printf '    %s%s%s\n' "$DIM" "$1" "$RESET"; }

BLOCKERS=()
OPTIONAL_MISSING=()
BREW=""

# Under Rosetta, `uname -m` is x86_64 and pip would fetch Intel wheels.
# Restart as native arm64 so every later tool sees the real architecture.
if [ "$(uname -m)" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    warn "This shell is running under Rosetta — re-launching as Apple Silicon."
    exec arch -arm64 /bin/bash "$0" "$@"
fi

ask_yes() {
    local prompt="$1"
    if [ "$INSTALL_TOOLS" -eq 1 ]; then return 0; fi
    if [ "$ASSUME_NO" -eq 1 ]; then return 1; fi
    if [ ! -t 0 ]; then return 1; fi
    local reply
    printf '    %s [Y/n] ' "$prompt"
    read -r reply || return 1
    case "$reply" in
        n|N|no|NO) return 1 ;;
        *) return 0 ;;
    esac
}

refresh_brew() {
    BREW=""
    local candidate
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            BREW="$candidate"
            break
        fi
    done
    if [ -n "$BREW" ]; then
        # Makes `ffmpeg` / `python3.12` resolvable in this shell after a
        # just-completed install, without requiring a new Terminal tab.
        eval "$("$BREW" shellenv)"
        export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
    fi
}

install_homebrew() {
    if [ -n "$BREW" ]; then return 0; fi
    if ! command -v curl >/dev/null 2>&1; then
        note "curl is required to install Homebrew and was not found."
        return 1
    fi
    note "Homebrew is not installed. The official installer may ask for your password."
    if ! ask_yes "Install Homebrew now?"; then
        return 1
    fi
    if [ "$INSTALL_TOOLS" -eq 1 ]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    refresh_brew
    [ -n "$BREW" ]
}

install_with_brew() {
    local formula="$1"
    if [ -z "$BREW" ] && ! install_homebrew; then
        note "Homebrew not found — install $formula manually."
        return 1
    fi
    printf '    installing %s...\n' "$formula"
    "$BREW" install "$formula"
}

python_version_string() {
    "$1" -c 'import sys; print("%d.%d" % (sys.version_info[0], sys.version_info[1]))' 2>/dev/null
}

python_is_supported() {
    # 3.10 is the documented floor. 3.14 is what this repo is verified against.
    # Newer versions are accepted and pip will fail loudly if wheels are missing.
    "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null
}

python_is_native_arm64() {
    "$1" -c 'import platform; raise SystemExit(0 if platform.machine() == "arm64" else 1)' 2>/dev/null
}

# Prefer 3.12: it has the most reliable PyTorch wheels. Fall back through
# other supported CPython versions before accepting a generic `python3`,
# which on a stock Mac is Apple's 3.9 stub and cannot run Demucs.
find_python() {
    local name dir candidate version best="" best_score=-1 score
    local names=(python3.12 python3.11 python3.13 python3.14 python3.10 python3)
    local dirs=(
        /opt/homebrew/bin
        /opt/homebrew/opt/python@3.12/bin
        /opt/homebrew/opt/python@3.11/bin
        /opt/homebrew/opt/python@3.13/bin
        /opt/homebrew/opt/python@3.14/bin
        /opt/homebrew/opt/python@3.10/bin
        /usr/local/bin
        /usr/local/opt/python@3.12/bin
        "${HOME}/.local/bin"
    )

    declare -a candidates=()
    for name in "${names[@]}"; do
        if command -v "$name" >/dev/null 2>&1; then
            candidates+=("$(command -v "$name")")
        fi
        for dir in "${dirs[@]}"; do
            candidates+=("${dir}/${name}")
        done
    done

    for candidate in "${candidates[@]}"; do
        [ -x "$candidate" ] || continue
        python_is_supported "$candidate" || continue
        python_is_native_arm64 "$candidate" || continue
        version="$(python_version_string "$candidate")"
        case "$version" in
            3.12) score=100 ;;
            3.11) score=90 ;;
            3.13) score=80 ;;
            3.14) score=70 ;;
            3.10) score=60 ;;
            *)    score=10 ;;
        esac
        if [ "$score" -gt "$best_score" ]; then
            best="$candidate"
            best_score="$score"
        fi
        # 3.12 is the preferred match — stop once we have one.
        [ "$score" -eq 100 ] && break
    done

    if [ -n "$best" ]; then
        printf '%s' "$best"
        return 0
    fi
    return 1
}

write_app_wrapper() {
    local macos_dir="$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$macos_dir"
    cat > "$macos_dir/ArielSplitter" <<'LAUNCHER'
#!/bin/bash
# Thin Finder wrapper. The real process is the SwiftPM binary, so existing
# ArielSplitter preferences keep working (no new bundle identifier).
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PACKAGE="$ROOT/Ariel's Splitter"
for bin in "$PACKAGE/.build/release/ArielSplitter" "$PACKAGE/.build/debug/ArielSplitter"; do
    if [ -x "$bin" ]; then
        exec "$bin"
    fi
done
osascript -e 'display dialog "ArielSplitter is not built yet.\n\nOpen Terminal in the MyTracks folder and run:\n\n    ./setup.sh --install-tools\n    ./run.sh" buttons {"OK"} default button 1 with title "ArielSplitter" with icon caution' >/dev/null
exit 1
LAUNCHER
    chmod +x "$macos_dir/ArielSplitter"
    cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ArielSplitter</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>local.arielsplitter.launcher</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ArielSplitter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDisplayName</key>
    <string>Ariel's Splitter</string>
</dict>
</plist>
PLIST
}

# ── 0. Machine ──────────────────────────────────────────────────────────
step "0. This Mac"

ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
    bad "Apple Silicon (M1 or later) is required — this Mac is $ARCH"
    note "Intel Macs are not supported. PyTorch/Demucs are only tested with the Apple GPU."
    BLOCKERS+=("Apple Silicon")
else
    ok "Apple Silicon ($ARCH)"
fi

OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
OS_MAJOR="${OS_VERSION%%.*}"
if [[ "$OS_MAJOR" =~ ^[0-9]+$ ]] && [ "$OS_MAJOR" -lt 14 ]; then
    bad "macOS 14 Sonoma or later is required (found $OS_VERSION)"
    BLOCKERS+=("macOS $OS_VERSION")
else
    ok "macOS $OS_VERSION"
fi

# torch + demucs + a Homebrew ffmpeg is a few GB; fail before a half-install.
AVAILABLE_KB="$(df -k "$REPO_ROOT" | awk 'NR==2 {print $4}')"
if [[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]] && [ "$AVAILABLE_KB" -lt 4194304 ]; then
    AVAILABLE_GB="$(awk -v k="$AVAILABLE_KB" 'BEGIN { printf "%.1f", k/1024/1024 }')"
    bad "less than 4 GB free on this volume (${AVAILABLE_GB} GB available)"
    note "The first install pulls PyTorch and, if requested, ffmpeg. Free some space and re-run."
    BLOCKERS+=("disk space")
else
    ok "enough free disk space"
fi

# ── 1. Build toolchain ──────────────────────────────────────────────────
step "1. Build toolchain"
if command -v swift >/dev/null 2>&1 && swift --version >/dev/null 2>&1; then
    ok "swift $(swift --version 2>/dev/null | head -1 | sed 's/.*Swift version \([0-9.]*\).*/\1/')"
    note "Full Xcode is not required; Command Line Tools are enough to build and run."
else
    bad "swift not found"
    note "Install the Command Line Tools — a system dialog will open."
    note "When it finishes, re-run ./setup.sh"
    xcode-select --install >/dev/null 2>&1 || true
    BLOCKERS+=("Command Line Tools (xcode-select --install)")
fi

refresh_brew
if [ -n "$BREW" ]; then
    ok "Homebrew — $BREW"
else
    warn "Homebrew not found"
    note "Needed to install ffmpeg (required) and a modern Python if this Mac only has Apple's 3.9."
    if install_homebrew; then
        ok "Homebrew — $BREW"
    else
        note "Continuing without Homebrew. You can re-run ./setup.sh --install-tools later."
    fi
fi

# ── 2. Python virtualenv ────────────────────────────────────────────────
step "2. Python virtualenv"
if [ "$RECREATE" -eq 1 ] && [ -d "$VENV_DIR" ]; then
    printf '    removing existing virtualenv...\n'
    rm -rf "$VENV_DIR"
fi

if [ -d "$VENV_DIR" ] && [ ! -x "$VENV_DIR/bin/python3" ]; then
    warn "existing virtualenv is unusable — removing it"
    rm -rf "$VENV_DIR"
fi

if [ -x "$VENV_DIR/bin/python3" ]; then
    VENV_PY="$VENV_DIR/bin/python3"
    if ! python_is_supported "$VENV_PY"; then
        bad "existing venv uses Python $(python_version_string "$VENV_PY"), need 3.10+"
        note "Re-run with --recreate after installing a newer Python (brew install python@3.12)."
        BLOCKERS+=("python version in venv")
    elif ! python_is_native_arm64 "$VENV_PY"; then
        bad "existing venv is not native Apple Silicon"
        note "It was probably created under Rosetta. Re-run with:  ./setup.sh --recreate"
        BLOCKERS+=("venv architecture")
    else
        ok "reusing $VENV_DIR (Python $(python_version_string "$VENV_PY"))"
    fi
else
    PYTHON_BIN=""
    if PYTHON_BIN="$(find_python)"; then
        note "using $PYTHON_BIN ($(python_version_string "$PYTHON_BIN"))"
    elif [ -n "$BREW" ] || [ "$INSTALL_TOOLS" -eq 1 ]; then
        if ask_yes "No Python 3.10+ found. Install python@3.12 with Homebrew?"; then
            if install_with_brew python@3.12; then
                refresh_brew
                PYTHON_BIN="$(find_python || true)"
            fi
        fi
    fi

    if [ -z "${PYTHON_BIN:-}" ]; then
        bad "no Python 3.10+ found"
        note "Apple's /usr/bin/python3 is 3.9 and cannot run this app."
        note "Install one:  brew install python@3.12"
        note "Or re-run:    ./setup.sh --install-tools"
        BLOCKERS+=("python3.10+")
    else
        printf '    creating virtualenv with %s...\n' "$PYTHON_BIN"
        if "$PYTHON_BIN" -m venv "$VENV_DIR"; then
            ok "created $VENV_DIR"
        else
            bad "could not create a virtualenv"
            note "If this is Apple's /usr/bin/python3, install a real interpreter:  brew install python@3.12"
            BLOCKERS+=("virtualenv")
        fi
    fi
fi

# ── 3. Python dependencies ──────────────────────────────────────────────
step "3. Python dependencies"
missing_python_modules() {
    "$VENV_DIR/bin/python3" - <<'PY'
import importlib.util
required = ["numpy", "torch", "torchaudio", "demucs", "soundfile", "librosa"]
print(",".join(n for n in required if importlib.util.find_spec(n) is None))
PY
}

if [ -x "$VENV_DIR/bin/python3" ]; then
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    REQ_HASH="$(shasum -a 256 "$REPO_ROOT/requirements.txt" | awk '{print $1}')"
    STAMP="$VENV_DIR/.requirements-sha256"
    NEED_PIP=1
    if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$REQ_HASH" ]; then
        if [ -z "$(missing_python_modules)" ]; then
            NEED_PIP=0
        fi
    fi

    if [ "$NEED_PIP" -eq 0 ]; then
        ok "dependencies already installed"
        ok "all required modules import"
    else
        note "first run downloads PyTorch — several hundred MB, often a few minutes"
        if ! "$VENV_DIR/bin/python3" -m pip install --upgrade pip setuptools wheel; then
            bad "could not upgrade pip"
            BLOCKERS+=("pip")
        elif ! "$VENV_DIR/bin/python3" -m pip install -r "$REPO_ROOT/requirements.txt"; then
            bad "pip install failed"
            note "A complete error is above. Common causes: no network, or this Python is too new for current wheels."
            BLOCKERS+=("python dependencies")
        else
            printf '%s\n' "$REQ_HASH" > "$STAMP"
            ok "installed from requirements.txt"
        fi

        # Verify the modules separate.py actually imports, rather than trusting pip.
        MISSING="$(missing_python_modules)"
        if [ -z "$MISSING" ]; then
            ok "all required modules import"
        else
            bad "missing modules: $MISSING"
            BLOCKERS+=("python modules: $MISSING")
        fi
    fi
else
    bad "virtualenv is unusable"
    BLOCKERS+=("virtualenv")
fi

# ── 4. ffmpeg (required) ────────────────────────────────────────────────
step "4. ffmpeg (required)"
FFMPEG=""
for candidate in "$(command -v ffmpeg 2>/dev/null || true)" /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg /opt/local/bin/ffmpeg; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        FFMPEG="$candidate"
        break
    fi
done
if [ -n "$FFMPEG" ]; then
    ok "ffmpeg — $FFMPEG"
else
    if ask_yes "ffmpeg is required and was not found. Install it with Homebrew?"; then
        if install_with_brew ffmpeg; then
            refresh_brew
            FFMPEG="$(command -v ffmpeg 2>/dev/null || true)"
            if [ -z "$FFMPEG" ]; then
                for candidate in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
                    [ -x "$candidate" ] && FFMPEG="$candidate" && break
                done
            fi
        fi
    fi
    if [ -n "${FFMPEG:-}" ]; then
        ok "ffmpeg — $FFMPEG"
    else
        bad "ffmpeg not found"
        note "Needed to read .m4a/.mp4 audio, which libsndfile cannot decode."
        note "Install with:  brew install ffmpeg"
        note "Or re-run:     ./setup.sh --install-tools"
        BLOCKERS+=("ffmpeg")
    fi
fi

# ── 5. yt-dlp (optional — only for URL downloads) ───────────────────────
step "5. yt-dlp (optional — only for URL downloads)"
YTDLP=""
for candidate in \
    "$VENV_DIR/bin/yt-dlp" \
    "$(command -v yt-dlp 2>/dev/null || true)" \
    /opt/homebrew/bin/yt-dlp \
    /usr/local/bin/yt-dlp \
    "$HOME/.local/bin/yt-dlp"
do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        YTDLP="$candidate"
        break
    fi
done
if [ -n "$YTDLP" ]; then
    ok "yt-dlp $("$YTDLP" --version 2>/dev/null | head -1) — $YTDLP"
else
    if ask_yes "yt-dlp was not found. Install it (needed only for URL downloads)?"; then
        if [ -x "$VENV_DIR/bin/python3" ] && "$VENV_DIR/bin/python3" -m pip install 'yt-dlp>=2024.8.0'; then
            YTDLP="$VENV_DIR/bin/yt-dlp"
        elif install_with_brew yt-dlp; then
            refresh_brew
            YTDLP="$(command -v yt-dlp 2>/dev/null || true)"
        fi
    fi
    if [ -n "${YTDLP:-}" ] && [ -x "$YTDLP" ]; then
        ok "yt-dlp $("$YTDLP" --version 2>/dev/null | head -1) — $YTDLP"
    else
        warn "yt-dlp not found"
        note "Only needed for the 'Download from URL' panel; everything else works without it."
        note "The next ./setup.sh will install it into the project venv via requirements.txt."
        OPTIONAL_MISSING+=("yt-dlp")
    fi
fi

# ── 6. Build ────────────────────────────────────────────────────────────
step "6. Build"
if [ ${#BLOCKERS[@]} -eq 0 ] && command -v swift >/dev/null 2>&1; then
    build_ok=0
    if [ "$RELEASE" -eq 1 ]; then
        note "building the release binary"
        if (cd "$PACKAGE_DIR" && swift build -c release 2>&1 | tail -5); then
            build_ok=1
        fi
    else
        if (cd "$PACKAGE_DIR" && swift build 2>&1 | tail -5); then
            build_ok=1
        fi
    fi
    if [ "$build_ok" -eq 1 ]; then
        ok "swift build succeeded"
        write_app_wrapper
        ok "wrote $APP_BUNDLE"
    else
        bad "swift build failed — see the output above"
        BLOCKERS+=("swift build")
    fi
else
    note "skipped while blockers remain"
fi

printf '\n%s──────────────────────────────────────────%s\n' "$BOLD" "$RESET"
if [ ${#BLOCKERS[@]} -eq 0 ]; then
    printf '%sSetup complete.%s Launch the app with:\n\n' "$GREEN$BOLD" "$RESET"
    printf '    ./run.sh\n\n'
    printf 'Or double-click ArielSplitter.app in this folder.\n'
    printf 'The first separation downloads the Demucs model (~500 MB) and needs internet.\n'
    if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
        printf '\nOptional, not installed: %s\n' "${OPTIONAL_MISSING[*]}"
    fi
    exit 0
else
    printf '%sSetup incomplete.%s Unresolved:\n\n' "$RED$BOLD" "$RESET"
    for blocker in "${BLOCKERS[@]}"; do printf '    - %s\n' "$blocker"; done
    printf '\nFix the above and re-run:\n'
    printf '    ./setup.sh --install-tools\n'
    exit 1
fi
