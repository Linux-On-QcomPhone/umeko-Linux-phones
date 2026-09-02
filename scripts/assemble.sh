#!/usr/bin/env bash
# Assemble the rootfs: extract ubuntu-base into the ext4 image, configure the
# system inside a qemu-aarch64 chroot (packages, locale, user, consoles),
# and install the kernel modules built by build_kernel.sh.
# Usage: scripts/assemble.sh devices/<a>.env [devices/<b>.env ...]
# With multiple devices, every device's rootfs overlay and post-assemble hook
# is applied (shared rootfs for the combined extlinux package); the first env
# provides the base system configuration.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
load_device "$@"

TARBALL="$CACHE_DIR/$(basename "$UBUNTU_BASE_URL")"
IMAGE="$BUILD_DIR/rootfs.img"
KREL="$(cat "$BUILD_DIR/kernelrelease")"
MODDIR="$BUILD_DIR/modinst/lib/modules/$KREL"

[[ -f "$TARBALL" ]] || die "ubuntu-base tarball missing, run build_rootfs.sh first"
[[ -f "$IMAGE" ]]   || die "rootfs image missing, run build_rootfs.sh first"
[[ -d "$MODDIR" ]]  || die "kernel modules missing ($MODDIR), run build_kernel.sh first"
command -v qemu-aarch64-static >/dev/null || die "qemu-user-static not installed"

mkdir -p "$MNT_DIR"

mount_image() {
    sudo mount -o loop "$IMAGE" "$MNT_DIR"
    # The image is still empty on a fresh build (tarball is extracted below),
    # so create the bind-mount targets before mounting them.
    sudo mkdir -p "$MNT_DIR/proc" "$MNT_DIR/sys" "$MNT_DIR/dev/pts"
    sudo mount --bind /proc "$MNT_DIR/proc"
    sudo mount --bind /sys "$MNT_DIR/sys"
    sudo mount --bind /dev "$MNT_DIR/dev"
    sudo mount --bind /dev/pts "$MNT_DIR/dev/pts"
}

umount_image() {
    for p in dev/pts dev sys proc; do
        sudo umount "$MNT_DIR/$p" 2>/dev/null || true
    done
    sudo umount "$MNT_DIR" 2>/dev/null || true
}
trap umount_image EXIT

log "mounting rootfs image and extracting ubuntu-base"
mount_image
sudo tar --numeric-owner -xpf "$TARBALL" -C "$MNT_DIR"

# --- chroot prerequisites -------------------------------------------------
# qemu user emulator (binfmt_misc with the F flag also works, keep both)
sudo cp "$(command -v qemu-aarch64-static)" "$MNT_DIR/usr/bin/"
# resolv.conf in ubuntu-base is a dangling symlink; provide real DNS in chroot
sudo rm -f "$MNT_DIR/etc/resolv.conf"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee "$MNT_DIR/etc/resolv.conf" >/dev/null
# never start services while chrooted (systemd is not running)
printf '#!/bin/sh\nexit 101\n' | sudo tee "$MNT_DIR/usr/sbin/policy-rc.d" >/dev/null
sudo chmod +x "$MNT_DIR/usr/sbin/policy-rc.d"

# --- in-chroot setup script ------------------------------------------------
sudo tee "$MNT_DIR/tmp/umeko-setup.sh" >/dev/null <<EOF
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends $ROOTFS_PACKAGES

# locale & timezone
locale-gen $LOCALE
update-locale LANG=$LOCALE
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# hostname
echo "$HOSTNAME" > /etc/hostname
printf '127.0.0.1\tlocalhost\n127.0.1.1\t$HOSTNAME\n' > /etc/hosts

# default user
useradd -m -s /bin/bash -G sudo,audio,video $DEFAULT_USER
echo '$DEFAULT_USER:$DEFAULT_PASSWORD' | chpasswd

# serial consoles (UART etc.)
$(for tty in $SERIAL_CONSOLES; do echo "systemctl enable serial-getty@$tty.service"; done)
systemctl enable ssh.service

# build provenance
cat > /etc/umeko-build-info <<INFO
device=$DEVICE_CODENAME ($DEVICE_NAME)
soc=$SOC
kernel=$KREL
ubuntu-base=$UBUNTU_BASE_URL
build-date=$(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

log "configuring system inside chroot (qemu-aarch64)"
sudo chroot "$MNT_DIR" bash /tmp/umeko-setup.sh

# --- kernel modules ---------------------------------------------------------
log "installing kernel modules ($KREL)"
sudo mkdir -p "$MNT_DIR/lib/modules"
sudo cp -a "$MODDIR" "$MNT_DIR/lib/modules/"

# --- device-specific customization (devices/<codename>/) --------------------
# Multi-device builds apply every device's overlay/hook in command-line order
# (the combined extlinux package shares one rootfs across devices).
collect_devices "$@"
for dir in "${DEVICE_DIRS[@]}"; do
    # rootfs/ overlay: files copied verbatim into the rootfs (systemd units,
    # modprobe.d confs, helper scripts, ...).
    if [[ -d "$dir/rootfs" ]]; then
        log "installing device overlay ($dir/rootfs)"
        sudo cp -a "$dir/rootfs/." "$MNT_DIR/"
    fi
done

# Optional prebuilt binaries fetched at build time (pinned URL + sha256),
# e.g. the webssh arm64 binary used by the autowebssh service.
if [[ -n "${WEBSSH_URL:-}" ]]; then
    WEBSSH_BIN="$CACHE_DIR/$(basename "$WEBSSH_URL")"
    if [[ ! -f "$WEBSSH_BIN" ]]; then
        log "downloading $WEBSSH_URL"
        curl -fL --retry 3 -o "$WEBSSH_BIN" "$WEBSSH_URL"
    fi
    echo "${WEBSSH_SHA256:?WEBSSH_SHA256 must be set with WEBSSH_URL}  $WEBSSH_BIN" | sha256sum -c -
    sudo install -D -m 755 "$WEBSSH_BIN" "$MNT_DIR/usr/local/lib/umeko/webssh"
fi

# post-assemble.sh: device hook executed inside the chroot after everything
# above (enable services, build/install extra software, ...).
for i in "${!DEVICE_DIRS[@]}"; do
    dir="${DEVICE_DIRS[$i]}"
    if [[ -f "$dir/post-assemble.sh" ]]; then
        log "running device post-assemble hook in chroot (${DEVICE_NAMES[$i]})"
        sudo cp "$dir/post-assemble.sh" "$MNT_DIR/tmp/umeko-device-setup.sh"
        sudo chroot "$MNT_DIR" env \
            DEVICE_CODENAME="$(basename "$dir")" DEVICE_NAME="${DEVICE_NAMES[$i]}" \
            SOC="$SOC" DEFAULT_USER="$DEFAULT_USER" \
            bash /tmp/umeko-device-setup.sh
        sudo rm -f "$MNT_DIR/tmp/umeko-device-setup.sh"
    fi
done

# --- cleanup ----------------------------------------------------------------
sudo rm -f "$MNT_DIR/usr/bin/qemu-aarch64-static" \
           "$MNT_DIR/usr/sbin/policy-rc.d" \
           "$MNT_DIR/tmp/umeko-setup.sh"
# restore the systemd-resolved symlink for normal boot
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf "$MNT_DIR/etc/resolv.conf"

log "rootfs assembled OK"
