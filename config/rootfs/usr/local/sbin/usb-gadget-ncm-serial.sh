#!/bin/sh

set -e

UDC="${ADBD_GADGET_UDC}"
if [ "${UDC}" ] && [ ! -e "/sys/class/udc/${UDC}" ]
then
    echo "ERROR: /sys/class/udc/${UDC} doesn't exist!" >&2
    exit 1
fi

if [ -z "${UDC}" ] && [ -d "/sys/class/udc" ]
then
    UDC="$(ls /sys/class/udc | head -1)"
fi

[ "${UDC}" ] || exit 0

modprobe libcomposite
CONFIGFS_DIR="/sys/kernel/config/usb_gadget/g1"

setup()
{
    mkdir -p ${CONFIGFS_DIR}/configs/c.1
    cd ${CONFIGFS_DIR}

    mkdir -p strings/0x409
    mkdir -p configs/c.1/strings/0x409

    echo 0x0100 > idProduct
    echo 0x18D1 > idVendor
    echo 0xEF > bDeviceClass
    echo 0x02 > bDeviceSubClass
    echo 0x01 > bDeviceProtocol

    echo "msm8916" > strings/0x409/manufacturer
    echo "NCM + Serial Gadget" > strings/0x409/product
    echo "0123456789" > strings/0x409/serialnumber

    echo "Multifunction Configuration" > configs/c.1/strings/0x409/configuration
    echo 250 > configs/c.1/MaxPower

    mkdir -p functions/ncm.usb0
    echo "02:11:22:33:44:55" > functions/ncm.usb0/dev_addr
    echo "02:11:22:33:44:56" > functions/ncm.usb0/host_addr
    ln -s functions/ncm.usb0 configs/c.1

    mkdir -p functions/acm.usb0
    ln -s functions/acm.usb0 configs/c.1
}

activate()
{
    echo "${UDC}" > ${CONFIGFS_DIR}/UDC
}

reset()
{
    if [ -d /sys/class/net/usb0 ]; then
        ip link set usb0 down 2>/dev/null || true
    fi

    rm -f ${CONFIGFS_DIR}/configs/c.1/acm.usb0 2>/dev/null || true
    rm -f ${CONFIGFS_DIR}/configs/c.1/ncm.usb0 2>/dev/null || true

    rmdir ${CONFIGFS_DIR}/functions/acm.usb0 2>/dev/null || true
    rmdir ${CONFIGFS_DIR}/functions/ncm.usb0 2>/dev/null || true

    rmdir ${CONFIGFS_DIR}/configs/c.1/strings/0x409/ 2>/dev/null || true
    rmdir ${CONFIGFS_DIR}/configs/c.1/ 2>/dev/null || true
    rmdir ${CONFIGFS_DIR}/strings/0x409/ 2>/dev/null || true
    rmdir ${CONFIGFS_DIR} 2>/dev/null || true
}

case "$1" in
    "setup") setup ;;
    "activate") activate ;;
    "reset") reset ;;
    *) echo "Usage: $0 [setup|activate|reset]"; exit 1 ;;
esac
