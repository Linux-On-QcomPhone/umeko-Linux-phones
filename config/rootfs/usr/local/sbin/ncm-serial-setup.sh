#!/bin/bash

ip link set usb0 up 2>/dev/null || true
ip addr add 192.168.100.1/24 dev usb0 2>/dev/null || true

exec /sbin/agetty -L 115200 ttyGS0 vt102
