#!/bin/bash
# vivo Y23L post-assemble hook (runs in the chroot, after the base setup).
set -e

# Mount the extlinux bootfs at /boot: kernel/dtbs/extlinux.conf live there,
# mounting it lets the running system inspect and update them.
# BOOTFS_UUID is fixed in config/base.env and written into the bootfs image
# by pack_extlinux.sh (mke2fs -U).
echo "UUID=${BOOTFS_UUID} /boot ext2 defaults 0 2" >> /etc/fstab


chmod 755 /usr/local/sbin/*.sh

systemctl enable buffyboard.service \
    ncm-serial.service \
    usb-gadget.service