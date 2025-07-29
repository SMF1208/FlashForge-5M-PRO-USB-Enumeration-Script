#!/bin/sh
# USB Serial Helper for persistent device names
# Based on USB bus address to create stable symlinks

if [ "$ACTION" = "add" ]; then
    # Get the USB bus address from sysfs
    USB_PATH=$(readlink -f /sys/class/tty/$MDEV/device | sed 's/.*\///')
    
    case "$USB_PATH" in
        *3-1.3.2*)
            ln -sf /dev/$MDEV /dev/ttyACM_port1
            ;;
        *3-1.3.1.2*)
            ln -sf /dev/$MDEV /dev/ttyACM_port2
            ;;
        *3-1.3.1.4*)
            ln -sf /dev/$MDEV /dev/ttyACM_port3
            ;;
    esac
fi