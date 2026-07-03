# 🏄 ESP32 Bluetooth Motor Control

> 🌍 **English version** | **[Русская версия →](README_ru.md)**

ESP32 + Bluetooth HID remote = brushless motor control

## 🚀 Quick Start

### 🛒 Required Components:
- **Bluetooth remote BT13**: [AliExpress](https://a.aliexpress.com/_EIvUKYS) *(tested and working)*
- **Motor controller**: [AliExpress](https://a.aliexpress.com/_EyfVQSQ)
- **Brushless motor**: [AliExpress](https://a.aliexpress.com/_Exu4xp0)
- **ESP32 board**: [AliExpress](https://a.aliexpress.com/_ExqenUe)

### ⚡ Automatic Installation

**Standard installation:**
```bash
# Clone repository
git clone https://github.com/sanfisko/sup-esurf-controller.git
cd sup-esurf-controller

# Run automatic installation
./install.sh
```

> 📡 **install.sh** - automatic Bluetooth device discovery and MAC address configuration.

**The script automatically:**
- ✅ Checks system dependencies (git, python3, curl, pip)
- ✅ Installs ESP-IDF if not found
- ✅ Checks and offers ESP-IDF updates
- ✅ Activates ESP-IDF environment
- ✅ Builds the project
- ✅ Finds ESP32
- ✅ Flashes ESP32 (speed 115200 for reliability)
- ✅ Starts monitoring (exit: **Ctrl+]**)

## 📡 Compatible Remotes

**Recommended**: [BT13 remote from AliExpress](https://a.aliexpress.com/_EIvUKYS) - tested and working ✅

<details>
<summary><small>📋 Technical requirements for remote (for developers)</small></summary>

### Bluetooth Remote Requirements:
- **Protocol**: Bluetooth Classic (BR/EDR) - NOT Bluetooth Low Energy (BLE)
- **Profile**: HID (Human Interface Device) 
- **Device Class**: Consumer Control or Generic HID
- **HID Usage Codes**: Must send specific codes (see table below)

### ✅ Tested Remotes:
| Model | Status | MAC Address | Notes |
|-------|--------|-------------|-------|
| **BT13** | ✅ Working | 8B:EB:75:4E:65:97 | Main test remote |

### 🔧 HID Usage Codes:
| Button | HID Usage | Function |
|--------|-----------|----------|
| Short + | 0x0004 | Increase speed by 1 level |
| Short - | 0x0008 | Decrease speed by 1 level |
| Long + | 0x0001 | Maximum forward speed |
| Long - | 0x0002 | Maximum reverse speed |
| STOP | 0x0010 | Stop motor |

### ❌ Incompatible Remotes:
- BLE (Bluetooth Low Energy) remotes
- Remotes without HID profile
- Remotes with different HID Usage codes
- WiFi remotes
- IR (infrared) remotes

</details>

<details>
<summary>🔧 Adding Support for New Remote</summary>

### 🔍 How to Check Compatibility:

1. **Check remote specifications**:
   - Must support "Bluetooth Classic" or "BR/EDR"
   - Must work as "HID device" or "Bluetooth keyboard/mouse"

2. **Test connection**:
   - Run project with your remote
   - Logs should show: `"Found device matching BT13 pattern"`
   - Button presses should show HID Usage codes

3. **Configure MAC address**:
   - If your remote is compatible but has different MAC address
   - Change `bt13_addr` in `main/main.c` to your remote's MAC

### 🛠️ Step-by-step Instructions:

1. **Find MAC address** of your remote
2. **Change MAC in code**: `main/main.c`, line 44
   ```c
   static esp_bd_addr_t bt13_addr = {0x8B, 0xEB, 0x75, 0x4E, 0x65, 0x97};
   ```
3. **Test HID codes**: enable logging and check what codes your remote sends
4. **Update button mapping** in `hid_host_cb()` function if needed

</details>

## 💡 How It Works

1. **ESP32** scans for Bluetooth devices
2. **Connects** to BT13 remote by MAC address
3. **Receives HID commands** from remote (button codes)
4. **Controls motor** through motor controller

## 🔧 System Requirements

The script automatically checks and suggests how to install:
- **git** - for downloading ESP-IDF
- **python3** - ESP-IDF foundation  
- **curl** - for downloading dependencies
- **pip3** - Python package manager

<details>
<summary>Installation commands for different systems</summary>

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install git python3 curl python3-pip

# CentOS/RHEL/Fedora  
sudo yum install git python3 curl python3-pip

# macOS
brew install git python3 curl
```

</details>

<details>
<summary>🛠️ Manual Installation (for experienced users)</summary>

#### 1. Requirements
- **ESP-IDF v5.4+** (required)
- ESP32 DevKit
- USB cable
- BT13 remote

#### 2. ESP-IDF Installation
```bash
mkdir -p ~/esp && cd ~/esp
git clone --recursive https://github.com/espressif/esp-idf.git
cd esp-idf && ./install.sh esp32 && . ./export.sh
```

#### 3. Build and Flash
```bash
# Activate ESP-IDF (in each new session)
. ~/esp/esp-idf/export.sh

# Set ESP32 target
idf.py set-target esp32

# Build project
idf.py build

# Flash (replace /dev/ttyUSB0 with your port)
idf.py -p /dev/ttyUSB0 flash

# Flash with reduced speed (for problematic cables)
idf.py -p /dev/ttyUSB0 -b 115200 flash

# Monitor (Ctrl+] to exit)
idf.py -p /dev/ttyUSB0 monitor
```

</details>

## 🔌 Connections

### Connection Diagram
```
ESP32 GPIO 25 → Controller PWM input (speed signal)
ESP32 GPIO 26 → Controller reverse (direction)
ESP32 GND     → Controller GND
ESP32 GPIO 2  → LED (status indication)
```

## 🎮 BT13 Control

| BT13 Button | Action | Description |
|-------------|--------|-------------|
| **+ short** | +1 speed level | Increases speed by 20% |
| **- short** | -1 speed level | Decreases speed by 20% |
| **+ long** | Maximum forward | Instantly 100% forward |
| **- long** | Maximum reverse | Instantly 100% reverse |
| **Middle** | STOP | Complete stop |

### Control Logic
- **5 speed levels**: from -5 (maximum reverse) to +5 (maximum forward)
- **0 level**: complete stop
- **Smooth control**: short presses for precise adjustment (20% step)
- **Quick control**: long presses for maximum speed
- **Auto-stop**: motor stops after 10 seconds if BT13 disconnects

### Work Monitoring
After flashing, ESP32 monitoring starts automatically:
- Shows BT13 connection logs
- Displays remote commands in real-time
- Shows current speed level and direction
- PWM signal status indication

**Monitor commands:**
- **Ctrl+]** - exit monitoring
- After exit - automatic connection analysis
- On successful connection - ESP-IDF removal suggestion

**Example monitor output:**
```
I (12345) BT_HID: HID Usage: 0x00B5 (+ short press)
I (12346) MOTOR: Command: Short +, Speed level = 1
I (12347) MOTOR: PWM: 51/255, Direction: FORWARD
I (12348) LED: State: ON
```

## 🔧 Configuration

### Changing Pins
Edit `main/main.c`:
```c
#define MOTOR_SPEED_PIN     GPIO_NUM_25  // PWM signal
#define MOTOR_DIR_PIN       GPIO_NUM_26  // Direction
#define LED_PIN             GPIO_NUM_2   // Indication
```

### Changing BT13 MAC Address

⚠️ **IMPORTANT**: Remote search happens **ONLY by MAC address**, not by device name!

#### 🔍 How to Find Your BT13 MAC Address

**Method 1: Through phone/computer**
1. Turn on BT13 (long press middle button, blue LED blinks)
2. On phone/PC open Bluetooth settings
3. Find "BT13" device in list
4. Check MAC address (format: `XX:XX:XX:XX:XX:XX`)

**Method 2: Through ESP32 logs**
1. Run project with any MAC address
2. Turn on BT13
3. In logs find line: `Found device: xx:xx:xx:xx:xx:xx`
4. This is your BT13 MAC address

#### 🔧 Changing MAC Address in Code

Open file `main/main.c` and find **line 44**:
```c
static esp_bd_addr_t bt13_addr = {0x8B, 0xEB, 0x75, 0x4E, 0x65, 0x97};
```

Replace MAC address with yours. **Example**:
- Your MAC: `AA:BB:CC:DD:EE:FF`
- Change to: `{0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF}`

```c
// Was (default):
static esp_bd_addr_t bt13_addr = {0x8B, 0xEB, 0x75, 0x4E, 0x65, 0x97};

// Now (your MAC):
static esp_bd_addr_t bt13_addr = {0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF};
```

#### 📝 MAC Address Conversion Rules
- MAC `8B:EB:75:4E:65:97` → `{0x8B, 0xEB, 0x75, 0x4E, 0x65, 0x97}`
- Each pair of characters → `0xXX`
- Remove `:` separators
- Add `0x` prefix to each pair

#### ✅ After Changes
1. Save file
2. Rebuild project: `idf.py build`
3. Flash ESP32: `idf.py flash`
4. Turn on BT13 and check connection

## 📊 Expected Logs

On successful connection you will see:
```
=== ESP32 HID Host Motor Control ===
System initialization...
Motor initialized
Bluetooth initialized
Searching for BT13 remote (MAC: 8B:EB:75:4E:65:97)...
Found device: 8b:eb:75:4e:65:97
Found BT13! Stopping discovery...
Connecting to BT13...
BT13 connected successfully!
Ready to receive commands from remote
```

When pressing buttons:
```
HID data (3 bytes): 01 B5 00
HID Usage: 0x00B5
Command: Short + (level increase)
Short +: Speed level = 1 (10% forward)
State: ON | Level: 1/10 | PWM: 25/255 | Direction: FORWARD
```

## 🔍 Diagnostics

### Flashing Problems

**ESP32 not found**
```bash
# Check available ports
ls /dev/tty* | grep -E "(USB|ACM)"

# Try different ports
idf.py -p /dev/ttyUSB1 flash
idf.py -p /dev/ttyACM0 flash
```

**Flashing errors / bad cable**
```bash
# Use reduced speed
idf.py -p /dev/ttyUSB0 -b 115200 flash

# Or very slow speed
idf.py -p /dev/ttyUSB0 -b 9600 flash

# Direct flashing through esptool
python -m esptool --chip esp32 -p /dev/ttyUSB0 -b 115200 \
  --before default_reset --after hard_reset write_flash \
  --flash_mode dio --flash_freq 40m --flash_size 2MB \
  0x1000 build/bootloader/bootloader.bin \
  0x10000 build/bt13_motor_control.bin \
  0x8000 build/partition_table/partition-table.bin
```

## 📝 License

MIT License - see [LICENSE](LICENSE) file

## 🤝 Support

If you encounter problems:
1. Check ESP32 logs through `idf.py monitor`
2. Ensure correct connections
3. Check ESP-IDF version (requires v5.4+)
4. Create issue in repository with detailed problem description

---

**Default BT13 MAC**: `8B:EB:75:4E:65:97`