#!/usr/bin/env bash
# Common helpers shared by all build scripts.
# Scripts run on a Linux host (GitHub Actions ubuntu-24.04 runner, or WSL2).
set -euo pipefail

log()  { printf '\033[1;32m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
BUILD_DIR="$REPO_ROOT/build"
OUT_DIR="$REPO_ROOT/out"
MNT_DIR="$BUILD_DIR/mnt"

# Load devices/<codename>.env (argument) plus config/base.env.
load_device() {
    local env_file="${1:?usage: $0 devices/<codename>.env}"
    [[ -f "$env_file" ]] || die "device config not found: $env_file"
    env_file="$(realpath "$env_file")"
    # shellcheck disable=SC1090
    source "$env_file"
    # shellcheck disable=SC1091
    source "$REPO_ROOT/config/base.env"
    # Per-device customization directory (kernel fragment, rootfs overlay,
    # post-assemble hook). All entries are optional.
    DEVICE_DIR="$REPO_ROOT/devices/$DEVICE_CODENAME"
    log "device: $DEVICE_NAME ($DEVICE_CODENAME, SoC $SOC)"
}
