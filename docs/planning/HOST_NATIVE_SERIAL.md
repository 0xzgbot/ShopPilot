# Host-Native Serial Communication (macOS)

## Overview

ShopPilot connects to CNC routers natively on macOS — no Windows VM, no Docker, no emulation. The app uses the macOS serial API directly to communicate with GRBL/FluidNC-compatible controllers over USB.

## Hardware Requirements

- **CNC router** with GRBL 1.1 or FluidNC firmware (USB CDC-ACM class)
- **USB cable**: Typically USB-A to USB-B (standard printer-style), or USB-C depending on controller board
- **macOS 14+** on Apple Silicon (native ShopPilot build target)

## Serial Port Detection

### Automatic Enumeration

ShopPilot scans `/dev` for serial devices at launch and whenever the user opens the Machine stage:

```swift
// Scans for cu.* and tty.* device entries
let contents = try fileManager.contentsOfDirectory(atPath: "/dev")
for item in contents where item.hasPrefix("cu.") || item.hasPrefix("tty.") {
    ports.append("/dev/\(item)")
}
```

### Common Device Paths

| Controller Board | USB Vendor ID | Product ID | macOS Path Pattern |
|---|---|---|---|
| Arduino Uno (GRBL) | 0x2341 | 0x0043 | `/dev/cu.usbmodem*` |
| BTT SKR Mini E3 | 0x0483 | 0x5740 | `/dev/cu.usbserial-*` |
| Native GRBL shield | varies | varies | `/dev/cu.usbmodem*` |
| FluidNC (ESP32) | 0x303a | varies | `/dev/cu.usbserial-*` |
| Generic USB CDC-ACM | any | any | `/dev/cu.*` or `/dev/tty.*` |

### Manual Port Selection

If automatic detection fails:

1. Open **System Report** (Apple menu → About This Mac → System Report)
2. Navigate to **USB** section
3. Find your CNC controller in the device tree
4. Note the **Device Path** (e.g., `IOService:/AppleACPIPlatformExpert/.../USB VID:PID/...`)
5. In ShopPilot, select **Serial** transport and choose the matching `/dev/cu.*` entry

## Serial Configuration Defaults

ShopPilot uses these defaults for GRBL-compatible controllers:

| Parameter | Default Value | Notes |
|---|---|---|
| Baud Rate | 115200 | Most common; some boards use 9600 or 250000 |
| Data Bits | 8 | Standard for all GRBL controllers |
| Parity | None | No parity checking |
| Stop Bits | One | Single stop bit |

### Changing Baud Rate

If your controller uses a non-standard baud rate:

1. Open **Preferences** in ShopPilot
2. Navigate to the Machine/Serial section
3. Change the baud rate from the dropdown (9600, 19200, 38400, 57600, 115200, 250000)
4. Click **Connect** to test

## Permissions & Security

### macOS Serial Port Access

macOS requires explicit permission for apps to access serial devices:

1. On first connection attempt, macOS may prompt for permission
2. If denied, grant via **System Settings → Privacy & Security → Serial Port** (macOS 14+)
3. Alternatively, add ShopPilot to **Full Disk Access** in System Settings

### Troubleshooting Permission Errors

If you see "Permission denied" or the port fails to open:

```bash
# Check current user's serial group membership
dscl . read /Groups/dialout

# Add your user to the dialout group (may require logout/login)
sudo dscl . -append /Groups/dialout GroupMembership $(whoami)

# Verify device permissions
ls -la /dev/cu.*
```

## GRBL Protocol Reference

### Status Query (`?`)

Send `?` to query machine status. Expected response format:

```
<Idle|MPos:-123.456:-234.567:-34.500|WPos:-123.456:-234.567:-34.500|FS:8000.0:1>
```

States: `Idle`, `Run`, `Done`, `Hold`, `Home`, `Alarm`, `Check`

### Realtime Commands

| Command | Character | Function |
|---|---|---|
| Hold | `!` (0x21) | Pause feed hold, maintain spindle/coolant |
| Resume | `~` (0x7E) | Resume from hold state |
| Reset | Ctrl+X (0x18) | Soft reset — abort all motion, return to idle |
| Status Query | `?` | Request current machine status |

### Streaming Protocol

ShopPilot uses **line-based ok-wait** streaming:

1. Send one G-code line
2. Wait for `ok` response from GRBL
3. Send next line
4. Repeat until complete

This is the safest streaming mode and prevents buffer overruns on low-bandwidth serial connections.

### Alarms & Errors

GRBL surfaces errors in responses:

```
ALARM:1 (Hard limit triggered)
error:-1 (Grbl fail)
error:32 (Alarm lock required)
```

ShopPilot displays these as red console messages with the alarm code and description.

## Simulator Mode

For development without hardware, ShopPilot includes a built-in simulator:

- **Transport type**: `Simulator` in the Machine stage dropdown
- **Port**: `/dev/tty.simulator` (virtual, no physical device needed)
- **Baud rate**: 115200
- **Behavior**: Simulates GRBL responses including status queries, ok-wait protocol, and alarm states

The simulator is enabled by default in DEBUG builds. In production builds, it remains available for testing without hardware.

## Troubleshooting

### Port Not Detected

1. Verify USB cable connects to the controller's **program/USB port** (not a power-only port)
2. Check that firmware is actually GRBL or FluidNC (some boards ship with different firmware)
3. Try a different USB cable — some cables are charge-only
4. Check `/dev` for new entries after plugging in: `ls /dev/cu.* /dev/tty.*`

### Connection Fails at 115200 Baud

Some older GRBL boards default to 9600 baud:

```bash
# Test with screen (macOS terminal)
screen /dev/cu.usbmodem* 9600
# Type $G and press Enter — if you get a response, the board uses 9600
# Type $$ to see all GRBL settings
# Change baud: $3=115200 (then re-open at new baud)
```

### "Device Busy" or "Resource Unavailable"

Another process may have the port open:

```bash
# Find processes using the serial port
lsof /dev/cu.usbmodem*

# Kill any stale processes (replace PID with actual number)
kill -9 <PID>
```

Common culprits: Arduino IDE Serial Monitor, PlatformIO, another instance of ShopPilot.

### macOS Updates Reset Permissions

After major macOS updates, serial permissions may need to be re-granted:

1. Open **System Settings → Privacy & Security**
2. Find **Serial Port** or **Full Disk Access**
3. Ensure ShopPilot is listed and toggled on
4. Restart ShopPilot

## Safety Notes

- **Software is not a substitute for hardware e-stop.** Always have a physical emergency stop accessible.
- The GRBL reset command (Ctrl+X) aborts all motion but does NOT disable the spindle or coolant. Manually verify these are off before approaching the machine.
- Disconnecting during streaming will cause an error and halt the job, but may leave the spindle running on some controllers. Always use Hold → Reset in sequence for safety.
