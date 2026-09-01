#!/usr/bin/env bash
# Build the kernel (Image.gz + device dtb + modules) for a device.
# Usage: scripts/build_kernel.sh devices/wt88047.env
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_device "$@"

KSRC="$REPO_ROOT/$KERNEL_SUBMODULE"
KBUILD="$BUILD_DIR/kernel"
[[ -e "$KSRC/.git" ]] || die "kernel submodule missing: $KSRC (run: git submodule update --init)"

# Wrap the cross compiler in ccache when available (big win on CI re-runs).
CCACHE=""
command -v ccache >/dev/null && CCACHE="ccache "

export ARCH=arm64
export CROSS_COMPILE="${CCACHE}aarch64-linux-gnu-"

log "configuring kernel ($KERNEL_DEFCONFIG)"
make -C "$KSRC" O="$KBUILD" "$KERNEL_DEFCONFIG"

# Merge the optional per-device config fragment (devices/<codename>/kernel.config).
FRAGMENT="$DEVICE_DIR/kernel.config"
if [[ -f "$FRAGMENT" ]]; then
    log "merging device kernel config fragment: $FRAGMENT"
    "$KSRC/scripts/kconfig/merge_config.sh" -m -O "$KBUILD" "$KBUILD/.config" "$FRAGMENT"
    make -C "$KSRC" O="$KBUILD" olddefconfig
fi

log "compiling Image.gz + $KERNEL_DTB + modules"
make -C "$KSRC" O="$KBUILD" -j"$(nproc)" Image.gz "$KERNEL_DTB" modules

log "installing modules to staging dir"
rm -rf "$BUILD_DIR/modinst"
make -C "$KSRC" O="$KBUILD" \
    INSTALL_MOD_PATH="$BUILD_DIR/modinst" INSTALL_MOD_STRIP=1 \
    modules_install

KREL="$(make -s -C "$KSRC" O="$KBUILD" kernelrelease)"
echo "$KREL" > "$BUILD_DIR/kernelrelease"

[[ -f "$KBUILD/arch/arm64/boot/Image.gz" ]] || die "Image.gz missing"
[[ -f "$KBUILD/arch/arm64/boot/dts/$KERNEL_DTB" ]] || die "dtb missing: $KERNEL_DTB"
log "kernel $KREL built OK"
