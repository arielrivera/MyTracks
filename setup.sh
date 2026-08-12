#!/usr/bin/env bash
#
# One-command setup for ArielSplitter.
#
# Creates a Python virtualenv, installs the separation dependencies, and checks
# for the command-line tools the app shells out to. Safe to re-run: it will
# reuse an existing virtualenv unless --recreate is passed.
#
#   ./setup.sh                 set up, and report anything missing
#   ./setup.sh --install-tools also install missing tools via Homebrew
#   ./setup.sh --recreate      delete and rebuild the virtualenv first
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$REPO_ROOT/venv"
PACKAGE_DIR="$REPO_ROOT/Ariel's Splitter"

INSTALL_TOOLS=0
RECREATE=0
for arg in "$@"; do
    case "$arg" in
        --install-tools) INSTALL_TOOLS=1 ;;
        --recreate)      RECREATE=1 ;;
        -h|--help)       sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# Homebrew is only needed to install missing tools; absence is not fatal.
BREW=""
for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && BREW="$candidate" && break
done

install_with_brew() {
    local formula="$1"
    if [ -z "$BREW" ]; then
        note "Homebrew not found — install $formula manually."
        return 1
    fi
    printf '    installing %s...\n' "$formula"
    "$BREW" install "$formula"
}

step "1. Build toolchain"
if command -v swift >/dev/null 2>&1; then
    ok "swift $(swift --version 2>/dev/null | head -1 | sed 's/.*Swift version \([0-9.]*\).*/\1/')"
    note "Full Xcode is not required; Command Line Tools are enough to build and run."
else
    bad "swift not found"
    note "Install the Command Line Tools:  xcode-select --install"
    BLOCKERS+=("swift toolchain")
fi

step "2. Python virtualenv"
if [ "$RECREATE" -eq 1 ] && [ -d "$VENV_DIR" ]; then
    printf '    removing existing virtualenv...\n'
    rm -rf "$VENV_DIR"
fi

if [ ! -d "$VENV_DIR" ]; then
    PYTHON_BIN=""
    for candidate in python3.12 python3.11 python3 python3.13; do
        if command -v "$candidate" >/dev/null 2>&1; then PYTHON_BIN="$candidate"; break; fi
    done
    if [ -z "$PYTHON_BIN" ]; then
        bad "no python3 found"
        note "Install one:  brew install python@3.12"
        BLOCKERS+=("python3")
    else
        printf '    creating virtualenv with %s...\n' "$PYTHON_BIN"
        "$PYTHON_BIN" -m venv "$VENV_DIR"
        ok "created $VENV_DIR"
    fi
else
    ok "reusing $VENV_DIR"
fi

step "3. Python dependencies"
if [ -x "$VENV_DIR/bin/python3" ]; then
    note "this can take several minutes on a first run (torch is large)"
    "$VENV_DIR/bin/python3" -m pip install --upgrade pip --quiet
    if "$VENV_DIR/bin/python3" -m pip install -r "$REPO_ROOT/requirements.txt" --quiet; then
        ok "installed from requirements.txt"
    else
        bad "pip install failed"
        BLOCKERS+=("python dependencies")
    fi

    # Verify the modules separate.py actually imports, rather than trusting pip.
    MISSING="$("$VENV_DIR/bin/python3" - <<'PY'
import importlib.util
required = ["numpy", "torch", "torchaudio", "demucs", "soundfile", "librosa"]
print(",".join(n for n in required if importlib.util.find_spec(n) is None))
PY
)"
    if [ -z "$MISSING" ]; then
        ok "all required modules import"
    else
        bad "missing modules: $MISSING"
        BLOCKERS+=("python modules: $MISSING")
    fi
else
    bad "virtualenv is unusable"
    BLOCKERS+=("virtualenv")
fi

step "4. ffmpeg (required)"
FFMPEG=""
for candidate in "$(command -v ffmpeg 2>/dev/null || true)" /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && FFMPEG="$candidate" && break
done
if [ -n "$FFMPEG" ]; then
    ok "ffmpeg — $FFMPEG"
else
    if [ "$INSTALL_TOOLS" -eq 1 ] && install_with_brew ffmpeg; then
        ok "ffmpeg installed"
    else
        bad "ffmpeg not found"
        note "Needed to read .m4a/.mp4 audio, which libsndfile cannot decode."
        note "Install with:  brew install ffmpeg"
        BLOCKERS+=("ffmpeg")
    fi
fi

step "5. yt-dlp (optional — only for URL downloads)"
YTDLP=""
for candidate in "$(command -v yt-dlp 2>/dev/null || true)" /opt/homebrew/bin/yt-dlp /usr/local/bin/yt-dlp "$HOME/.local/bin/yt-dlp"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && YTDLP="$candidate" && break
done
if [ -n "$YTDLP" ]; then
    ok "yt-dlp $("$YTDLP" --version 2>/dev/null) — $YTDLP"
else
    if [ "$INSTALL_TOOLS" -eq 1 ] && install_with_brew yt-dlp; then
        ok "yt-dlp installed"
    else
        warn "yt-dlp not found"
        note "Only needed for the 'Download from URL' panel; everything else works without it."
        note "Install with:  brew install yt-dlp"
        OPTIONAL_MISSING+=("yt-dlp")
    fi
fi

step "6. Build"
if [ ${#BLOCKERS[@]} -eq 0 ] && command -v swift >/dev/null 2>&1; then
    if (cd "$PACKAGE_DIR" && swift build 2>&1 | tail -3); then
        ok "swift build succeeded"
    else
        bad "swift build failed — see the output above"
        BLOCKERS+=("swift build")
    fi
else
    note "skipped while blockers remain"
fi

printf '\n%s──────────────────────────────────────────%s\n' "$BOLD" "$RESET"
if [ ${#BLOCKERS[@]} -eq 0 ]; then
    printf '%sSetup complete.%s Run the app with:\n\n' "$GREEN$BOLD" "$RESET"
    # Absolute path, quoted: the directory name contains a space, and a tilde
    # inside quotes would not expand.
    printf '    cd "%s"\n    swift run ArielSplitter\n' "$PACKAGE_DIR"
    if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
        printf '\nOptional, not installed: %s\n' "${OPTIONAL_MISSING[*]}"
    fi
    exit 0
else
    printf '%sSetup incomplete.%s Unresolved:\n\n' "$RED$BOLD" "$RESET"
    for blocker in "${BLOCKERS[@]}"; do printf '    - %s\n' "$blocker"; done
    printf '\nFix the above and re-run ./setup.sh\n'
    exit 1
fi
