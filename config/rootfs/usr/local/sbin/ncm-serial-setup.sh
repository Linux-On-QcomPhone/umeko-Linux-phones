#!/bin/bash

# usb0 appears when the NCM function binds (usb-gadget.service); wait
# briefly in case we raced ahead of it.
i=0
while [ ! -d /sys/class/net/usb0 ] && [ "$i" -lt 15 ]; do
    i=$((i+1)); sleep 1
done

ip link set usb0 up 2>/dev/null || true
ip addr add 192.168.100.1/24 dev usb0 2>/dev/null || true

exec /sbin/agetty -L 115200 ttyGS0 vt102
