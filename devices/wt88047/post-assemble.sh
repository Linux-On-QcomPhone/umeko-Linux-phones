#!/bin/bash
# wt88047 post-assemble hook — runs inside the qemu-aarch64 chroot at the end
# of assemble.sh, after the base system, kernel modules and the rootfs/
# overlay are in place. Device env vars (DEVICE_CODENAME, DEFAULT_USER, ...)
# are passed in the environment.
set -e

# The overlay may lose executable bits when the git working tree lives on a
# Windows checkout, so fix permissions explicitly.
chmod 644 /etc/systemd/system/*.service /etc/modprobe.d/*.conf
chmod 755 /usr/local/lib/umeko/*.sh

# Services adopted from https://gitee.com/meiziyang2023/umeko-env-init
# (plus umeko-modem-firmware, which pulls the WiFi/modem firmware from the
# phone's own modem partition; ttyGS0 comes from the built-in g_serial
# gadget, see kernel.config).
systemctl enable \
    umeko-modem-firmware.service \
    autottyGS0.service \
    autoresize.service \
    auto_rmi4_reload.service \
    autowebssh.service \
    autocanup.service
