# FlashForge-5M-PRO-USB-Enumeration-Script
# This is a set of scripts to resolve the issue of random USB assignments on boot for the flash forge 5M pro.  THIS HAS NOT BEEN TESTED WITH FORGEX, IT IS KNOWN WORKING ON ORIGIANL KLIPPER MOD

## Problem Description

When using the FlashForge AD5M Pro Klipper mod with multiple external MCUs connected via USB hub, the USB enumeration order changes randomly on boot and after `FIRMWARE_RESTART` commands. This causes MCU communication errors because the device paths (like `/dev/ttyACM0`, `/dev/ttyACM1`, etc.) get scrambled, and Klipper tries to connect to the wrong MCU boards.

**Symptoms:**
- Random MCU communication errors after reboots
- Wrong temperature readings from sensors
- Extruders responding in wrong order after firmware restarts
- Works correctly sometimes, fails other times (depending on USB enumeration luck)

## Root Cause

The minimal Buildroot Linux system on the AD5M Pro doesn't maintain consistent USB device enumeration order. Each time the system boots or MCUs are reset (via `FIRMWARE_RESTART`), the USB devices can enumerate in a different order, causing `/dev/ttyACM0-3` assignments to change randomly.

## Solution Overview

Create a background daemon that continuously monitors USB device changes and automatically creates consistent symlinks based on MCU serial numbers, then restarts Klipper when changes are detected.

## Implementation

### Step 1: Find Your MCU Serial Numbers

First, identify each MCU's unique serial number:

```bash
for i in 0 1 2 3; do
    echo "ttyACM$i: $(cat /sys/class/tty/ttyACM$i/device/../serial)"
done
```

Record which serial belongs to which MCU board.

### Step 2: Create MCU Assignment Script

Create `/root/assign_mcus.sh`:

```bash
#!/bin/sh

LOG_FILE="/tmp/mcu_mapping.log"

log_message() {
    echo "$(date): $1" >> $LOG_FILE
}

log_message "Starting MCU serial ID mapping script"

# Configure your actual MCU serial IDs here
MCU_KCM_SERIAL="34FFD70531304D3920890443" 
MCU_KCM2_SERIAL="34FFD70531304D3925862443"
MCU_ECM_SERIAL="32FFD7053130433213752343"
MCU_HEAD_SERIAL="34FFDB0531304D3936582443"

# Wait for USB devices to enumerate
sleep 10

# Remove old symlinks
rm -f /dev/mcu_kcm /dev/mcu_kcm2 /dev/mcu_ecm /dev/mcu_head

log_message "Removed old symlinks"

# Function to find device by serial ID
find_device_by_identifier() {
    local identifier=$1
    local symlink_name=$2
    
    for acm_dev in /dev/ttyACM*; do
        if [ -e "$acm_dev" ]; then
            local acm_num=$(basename "$acm_dev" | sed 's/ttyACM//')
            local sysfs_base="/sys/class/tty/ttyACM${acm_num}/device"
            
            for serial_path in "../serial" "../../serial" "../../../serial"; do
                local dev_serial=$(cat "${sysfs_base}/${serial_path}" 2>/dev/null)
                if [ -n "$dev_serial" ] && echo "$dev_serial" | grep -q "$identifier"; then
                    ln -sf "$acm_dev" "/dev/$symlink_name"
                    log_message "Created symlink: $acm_dev -> /dev/$symlink_name (serial: $dev_serial)"
                    return 0
                fi
            done
        fi
    done
    
    log_message "WARNING: Could not find device with identifier: $identifier"
    return 1
}

# Map each MCU to its symlink
log_message "Mapping MCU identifiers to symlinks..."

find_device_by_identifier "$MCU_KCM_SERIAL" "mcu_kcm"
find_device_by_identifier "$MCU_KCM2_SERIAL" "mcu_kcm2" 
find_device_by_identifier "$MCU_ECM_SERIAL" "mcu_ecm"
find_device_by_identifier "$MCU_HEAD_SERIAL" "mcu_head"

log_message "MCU mapping script completed"
```

Make it executable:
```bash
chmod +x /root/assign_mcus.sh
```

### Step 3: Create MCU Monitor Daemon

Create `/root/mcu_monitor.sh`:

```bash
#!/bin/sh

# MCU Monitor Daemon
LOG_FILE="/tmp/mcu_monitor.log"
PIDFILE="/var/run/mcu_monitor.pid"

# Configure your MCU serial IDs here
MCU_KCM_SERIAL="34FFD70531304D3920890443" 
MCU_KCM2_SERIAL="34FFD70531304D3925862443"
MCU_ECM_SERIAL="32FFD7053130433213752343"
MCU_HEAD_SERIAL="34FFDB0531304D3936582443"

log_message() {
    echo "$(date): $1" >> $LOG_FILE
}

create_symlinks() {
    rm -f /dev/mcu_kcm /dev/mcu_kcm2 /dev/mcu_ecm /dev/mcu_head
    local changes_made=0
    
    for acm_dev in /dev/ttyACM*; do
        if [ -e "$acm_dev" ]; then
            local acm_num=$(basename "$acm_dev" | sed 's/ttyACM//')
            local dev_serial=$(cat "/sys/class/tty/ttyACM${acm_num}/device/../serial" 2>/dev/null)
            
            case "$dev_serial" in
                "$MCU_KCM_SERIAL")
                    ln -sf "$acm_dev" "/dev/mcu_kcm"
                    log_message "Linked mcu_kcm -> $acm_dev"
                    changes_made=1
                    ;;
                "$MCU_KCM2_SERIAL")
                    ln -sf "$acm_dev" "/dev/mcu_kcm2"
                    log_message "Linked mcu_kcm2 -> $acm_dev"
                    changes_made=1
                    ;;
                "$MCU_ECM_SERIAL")
                    ln -sf "$acm_dev" "/dev/mcu_ecm"
                    log_message "Linked mcu_ecm -> $acm_dev"
                    changes_made=1
                    ;;
                "$MCU_HEAD_SERIAL")
                    ln -sf "$acm_dev" "/dev/mcu_head"
                    log_message "Linked mcu_head -> $acm_dev"
                    changes_made=1
                    ;;
            esac
        fi
    done
    
    return $changes_made
}

get_usb_state() {
    ls -la /dev/ttyACM* 2>/dev/null | sort
}

monitor_usb() {
    log_message "MCU Monitor Daemon started"
    last_state=""
    current_state=""
    
    while true; do
        current_state=$(get_usb_state)
        
        if [ "$current_state" != "$last_state" ]; then
            log_message "USB device state changed"
            sleep 2
            
            if create_symlinks; then
                log_message "MCU symlinks updated"
                sleep 2
                log_message "Restarting Klipper to use corrected symlinks"
                /etc/init.d/S60klipper restart
                log_message "Klipper restart initiated"
            fi
            
            last_state="$current_state"
        fi
        
        sleep 3
    done
}

case "$1" in
    start)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            echo "MCU monitor already running"
            exit 1
        fi
        
        echo "Starting MCU monitor daemon..."
        monitor_usb &
        echo $! > "$PIDFILE"
        log_message "MCU Monitor Daemon started with PID $!"
        ;;
    stop)
        if [ -f "$PIDFILE" ]; then
            pid=$(cat "$PIDFILE")
            if kill "$pid" 2>/dev/null; then
                echo "MCU monitor stopped"
                log_message "MCU Monitor Daemon stopped"
            else
                echo "MCU monitor was not running"
            fi
            rm -f "$PIDFILE"
        else
            echo "MCU monitor is not running"
        fi
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
            echo "MCU monitor is running (PID: $(cat $PIDFILE))"
        else
            echo "MCU monitor is not running"
            rm -f "$PIDFILE" 2>/dev/null
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac

exit 0
```

Make it executable:
```bash
chmod +x /root/mcu_monitor.sh
```

### Step 4: Update Klipper Startup Script

Modify `/etc/init.d/S60klipper` to integrate the MCU monitor:

```bash
start() {
    mkdir -p $(dirname $KLIPPER_LOG)
    sleep 30
    # Start Klipper in background
    start-stop-daemon -S -b -m -p $PID_FILE -N $KLIPPER_NICENESS --exec $PYTHON -- $KLIPPER $KLIPPER_CONF -l $KLIPPER_LOG -a $KLIPPER_UDS
    # Wait for Klipper to start initializing
    sleep 10
    # Run initial MCU assignment
    /root/assign_mcus.sh
    # Start MCU monitor daemon
    /root/mcu_monitor.sh start
}

stop() {
    /root/mcu_monitor.sh stop
    start-stop-daemon -K -q -p $PID_FILE
}
```

### Step 5: Update Your Klipper Configuration

In your MCU configuration files, use the consistent symlink paths:

```ini
[mcu kcm]
serial: /dev/mcu_kcm

[mcu kcm2]
serial: /dev/mcu_kcm2

[mcu ecm]
serial: /dev/mcu_ecm

[mcu head]
serial: /dev/mcu_head
```

## How It Works

1. **Boot Process**: System boots, waits for USB stabilization, starts Klipper, runs initial MCU assignment, starts monitor daemon
2. **Continuous Monitoring**: Daemon monitors USB device changes every 3 seconds
3. **Automatic Recovery**: When USB enumeration changes (after firmware restarts), daemon detects it, updates symlinks based on serial numbers, and automatically restarts Klipper
4. **Consistent Mapping**: MCUs always get mapped to correct symlinks regardless of enumeration order

## Benefits

- **Fully Automatic**: No manual intervention required after firmware restarts
- **Reliable**: Based on hardware serial numbers, not enumeration order
- **Transparent**: Works with existing Klipper configurations
- **Robust**: Handles multiple MCUs with complex setups

## Important Notes

- Replace the serial numbers in the scripts with your actual MCU serial IDs
- Ensure all MCUs are powered on during boot
- The solution works with any number of MCUs (modify scripts accordingly)
- Monitor logs at `/tmp/mcu_monitor.log` and `/tmp/mcu_mapping.log` for troubleshooting

## Testing

After implementation:
1. Reboot printer - should work automatically
2. Perform `FIRMWARE_RESTART` - should automatically recover
3. Check daemon status: `/root/mcu_monitor.sh status`
4. Verify symlinks: `ls -la /dev/mcu_*`

This solution completely eliminates USB enumeration issues with multi-MCU FlashForge AD5M Pro setups running the Klipper mod.
