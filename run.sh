#!/usr/bin/env bash
#
# Launch ArielSplitter. If this checkout is not set up yet, runs setup.sh
# first so a new Mac can go from clone to window in one command:
#
#   ./setup.sh --install-tools && ./run.sh
#   ./run.sh                    # also acceptable; will set up if needed
#
# Flags are forwarded to setup.sh when a setup pass is required
# (--install-tools, --recreate, --release, ...). --no-setup skips that
# and only launches an already-built binary.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$REPO_ROOT/Ariel's Splitter"

# Same PATH prefix as setup.sh: a GUI-spawned or fresh shell may not see
# Homebrew, and we need `swift` if we have to build.
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${PATH}"

if [ "$(uname -m)" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ]; then
    exec arch -arm64 /bin/bash "$0" "$@"
fi

NO_SETUP=0
SETUP_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-setup) NO_SETUP=1 ;;
        -h|--help)
            sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) SETUP_ARGS+=("$arg") ;;
    esac
done

find_binary() {
    local bin
    for bin in \
        "$PACKAGE_DIR/.build/release/ArielSplitter" \
        "$PACKAGE_DIR/.build/debug/ArielSplitter"
    do
        if [ -x "$bin" ]; then
            printf '%s' "$bin"
            return 0
        fi
    done
    return 1
}

needs_setup() {
    [ -x "$REPO_ROOT/venv/bin/python3" ] || return 0
    find_binary >/dev/null || return 0
    return 1
}

if needs_setup; then
    if [ "$NO_SETUP" -eq 1 ]; then
        echo "ArielSplitter is not set up yet. From this folder run:" >&2
        echo "  ./setup.sh --install-tools" >&2
        exit 1
    fi
    echo "This copy is not ready yet — running setup..."
    "$REPO_ROOT/setup.sh" "${SETUP_ARGS[@]+"${SETUP_ARGS[@]}"}"
fi

BIN="$(find_binary)" || {
    echo "Setup finished but the app binary was not found." >&2
    echo "Try:  ./setup.sh --recreate" >&2
    exit 1
}

exec "$BIN"
