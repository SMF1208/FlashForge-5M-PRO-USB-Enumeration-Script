# FlashForge-5M-PRO-USB-Enumeration-Script
# This is a script designed to create static symlinks for USB hubs on the FlashForge 5M Pro.  It was designed to use CoPrint's KCM 8 Color set.
## Problem Description

When using the FlashForge AD5M Pro Klipper mod with multiple external MCUs connected via USB hub, the USB enumeration order changes randomly on boot and after `FIRMWARE_RESTART` commands. This causes MCU communication errors because the device paths (like `/dev/ttyACM0`, `/dev/ttyACM1`, etc.) get scrambled, and Klipper tries to connect to the wrong MCU boards.

**Symptoms:**
- Random MCU communication errors after reboots
- Wrong temperature readings from sensors
- Extruders responding in wrong order after firmware restarts
- Works correctly sometimes, fails other times (depending on USB enumeration luck)

Step 1: Create Helper Script
SSH into printer (root/klipper) and create the script:

`nano /usr/libexec/usb-serial-helper.sh`

Paste this content:
```
#!/bin/sh
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
```
Make it executable:

`chmod +x /usr/libexec/usb-serial-helper.sh`

Step 2: Update mdev Configuration
Edit mdev config:

`nano /etc/mdev.conf`

Add this line after the ttyUSB line:

`ttyACM[0-9]*    root:root 660 */usr/libexec/usb-serial-helper.sh`

Step 3: Restart mdev and Test

`killall mdev`

`/sbin/mdev -s`

Check if symlinks were created:

`bashls -la /dev/ttyACM_*`

Step 4: Update Klipper Config
In your printer.cfg, use the persistent names instead of ttyACM numbers:
```
ini[mcu]
serial: /dev/ttyACM_port1  # Instead of /dev/ttyACM0
```
Customization
Important: The USB bus addresses (3-1.3.2, etc.) in the script are specific to the AD5M Pro's USB hub layout that came from CoPrint. To find your specific addresses:
`bashdmesg | grep ttyACM`
Look for patterns like 3-1.3.2:1.0 and update the script accordingly.

Result:
/dev/ttyACM_port1, /dev/ttyACM_port2, /dev/ttyACM_port3 will always point to the same physical USB ports
ttyACM numbers can scramble, but your symlinks remain stable
Klipper configuration stays consistent across reboots

This solution completely eliminates USB enumeration issues with multi-MCU FlashForge AD5M Pro setups running the Klipper mod.
