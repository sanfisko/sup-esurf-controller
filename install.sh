#!/bin/bash

# Universal installation script with Bluetooth scanning for sup-esurf-controller project
# Author: sanfisko
# Repository: https://github.com/sanfisko/sup-esurf-controller
# Version: install.sh - with automatic Bluetooth device discovery support

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Constants
ESP_IDF_VERSION="v5.4.1"
ESP_DIR="$HOME/esp"
ESP_IDF_PATH="$ESP_DIR/esp-idf"
PROJECT_DIR="$(pwd)"
FLASH_SPEED="115200"
MAIN_C_FILE="$PROJECT_DIR/main/main.c"

# Function to print header
print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         ESP32 Bluetooth Motor Control Setup (EN)            ║${NC}"
    echo -e "${BLUE}║       github.com/sanfisko/sup-esurf-controller     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to check and install system dependencies
check_system_dependencies() {
    echo -e "${BLUE}🔍 Checking system dependencies...${NC}"
    
    local missing_deps=()
    local os_type=$(uname)
    
    # Check basic tools
    if ! command -v git >/dev/null 2>&1; then
        missing_deps+=("git")
    fi
    
    if ! command -v cmake >/dev/null 2>&1; then
        missing_deps+=("cmake")
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        missing_deps+=("python3")
    fi
    
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        missing_deps+=("python3-pip")
    fi
    
    # For Linux check additional dependencies
    if [ "$os_type" != "Darwin" ]; then
        if ! command -v make >/dev/null 2>&1; then
            missing_deps+=("build-essential")
        fi
        
        if ! command -v gcc >/dev/null 2>&1; then
            missing_deps+=("gcc")
        fi
        
        # Check libusb for ESP32 communication
        if ! ldconfig -p | grep -q libusb; then
            missing_deps+=("libusb-1.0-0-dev")
        fi
    fi
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All system dependencies are installed${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}💡 Would you like to install them automatically?${NC}"
        read -p "Install missing dependencies? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if install_system_dependencies "${missing_deps[@]}"; then
                return 0
            else
                return 1
            fi
        else
            echo -e "${CYAN}Install manually:${NC}"
            if [ "$os_type" = "Darwin" ]; then
                echo -e "${YELLOW}macOS: brew install ${missing_deps[*]}${NC}"
            else
                echo -e "${YELLOW}Ubuntu/Debian: sudo apt install ${missing_deps[*]}${NC}"
                echo -e "${YELLOW}CentOS/RHEL: sudo yum install ${missing_deps[*]}${NC}"
            fi
            return 1
        fi
    fi
}

# Function to install system dependencies
install_system_dependencies() {
    local deps=("$@")
    local os_type=$(uname)
    
    echo -e "${BLUE}🔧 Installing system dependencies...${NC}"
    
    if [ "$os_type" = "Darwin" ]; then
        echo -e "${BLUE}🍎 Installing dependencies for macOS...${NC}"
        if command -v brew >/dev/null 2>&1; then
            brew install "${deps[@]}"
        else
            echo -e "${RED}❌ Homebrew not found. Install brew first${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}🐧 Installing dependencies for Linux...${NC}"
        
        # Determine distribution and install packages
        if command -v apt >/dev/null 2>&1; then
            echo -e "${CYAN}Updating package list...${NC}"
            sudo apt update
            echo -e "${CYAN}Installing: ${deps[*]}${NC}"
            
            # Convert some package names for apt
            local apt_deps=()
            for dep in "${deps[@]}"; do
                case "$dep" in
                    "python3-pip")
                        apt_deps+=("python3-pip")
                        ;;
                    "build-essential")
                        apt_deps+=("build-essential")
                        ;;
                    "libusb-1.0-0-dev")
                        apt_deps+=("libusb-1.0-0-dev")
                        ;;
                    *)
                        apt_deps+=("$dep")
                        ;;
                esac
            done
            
            sudo apt install -y "${apt_deps[@]}"
            
        elif command -v yum >/dev/null 2>&1; then
            echo -e "${CYAN}Installing via yum: ${deps[*]}${NC}"
            # Convert package names for yum
            local yum_deps=()
            for dep in "${deps[@]}"; do
                case "$dep" in
                    "python3-pip")
                        yum_deps+=("python3-pip")
                        ;;
                    "build-essential")
                        yum_deps+=("gcc" "gcc-c++" "make")
                        ;;
                    "libusb-1.0-0-dev")
                        yum_deps+=("libusb1-devel")
                        ;;
                    *)
                        yum_deps+=("$dep")
                        ;;
                esac
            done
            sudo yum install -y "${yum_deps[@]}"
            
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "${CYAN}Installing via dnf: ${deps[*]}${NC}"
            # Convert package names for dnf
            local dnf_deps=()
            for dep in "${deps[@]}"; do
                case "$dep" in
                    "python3-pip")
                        dnf_deps+=("python3-pip")
                        ;;
                    "build-essential")
                        dnf_deps+=("gcc" "gcc-c++" "make")
                        ;;
                    "libusb-1.0-0-dev")
                        dnf_deps+=("libusb1-devel")
                        ;;
                    *)
                        dnf_deps+=("$dep")
                        ;;
                esac
            done
            sudo dnf install -y "${dnf_deps[@]}"
        else
            echo -e "${RED}❌ Unknown package manager${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ System dependencies installed${NC}"
    return 0
}

# Function to automatically install Bluetooth packages
install_bluetooth_packages() {
    local os_type=$(uname)
    
    if [ "$os_type" = "Darwin" ]; then
        echo -e "${BLUE}🍎 Installing blueutil for macOS...${NC}"
        if command -v brew >/dev/null 2>&1; then
            brew install blueutil
        else
            echo -e "${RED}❌ Homebrew not found. Install brew first${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}🐧 Installing Bluetooth packages for Linux...${NC}"
        
        # Determine distribution
        if command -v apt >/dev/null 2>&1; then
            echo -e "${CYAN}Updating package list...${NC}"
            sudo apt update
            echo -e "${CYAN}Installing bluetooth, bluez, bluez-tools...${NC}"
            sudo apt install -y bluetooth bluez bluez-tools
        elif command -v yum >/dev/null 2>&1; then
            echo -e "${CYAN}Installing bluez, bluez-tools...${NC}"
            sudo yum install -y bluez bluez-tools
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "${CYAN}Installing bluez, bluez-tools...${NC}"
            sudo dnf install -y bluez bluez-tools
        else
            echo -e "${RED}❌ Unknown package manager${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Function to check Bluetooth environment
check_bluetooth_tools() {
    echo -e "${BLUE}🔍 Checking Bluetooth tools...${NC}"
    
    local tools_available=false
    local os_type=$(uname)
    
    # Check blueutil for macOS
    if [ "$os_type" = "Darwin" ] && command -v blueutil >/dev/null 2>&1; then
        echo -e "${GREEN}✅ blueutil found (macOS)${NC}"
        tools_available=true
    fi
    
    # Check bluetoothctl
    if command -v bluetoothctl >/dev/null 2>&1; then
        echo -e "${GREEN}✅ bluetoothctl found${NC}"
        tools_available=true
    fi
    
    # Check hcitool
    if command -v hcitool >/dev/null 2>&1; then
        echo -e "${GREEN}✅ hcitool found${NC}"
        tools_available=true
    fi
    
    # Check rfkill (Linux only)
    if [ "$os_type" != "Darwin" ] && command -v rfkill >/dev/null 2>&1; then
        echo -e "${GREEN}✅ rfkill found${NC}"
    fi
    
    if [ "$tools_available" = false ]; then
        echo -e "${YELLOW}⚠️  Bluetooth tools not found${NC}"
        echo -e "${BLUE}💡 Would you like to install them automatically?${NC}"
        read -p "Install Bluetooth packages? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if install_bluetooth_packages; then
                echo -e "${GREEN}✅ Bluetooth packages installed${NC}"
                return 0
            else
                echo -e "${RED}❌ Error installing packages${NC}"
                echo -e "${CYAN}Install manually:${NC}"
                if [ "$os_type" = "Darwin" ]; then
                    echo -e "${YELLOW}macOS: brew install blueutil${NC}"
                else
                    echo -e "${YELLOW}Ubuntu/Debian: sudo apt install bluetooth bluez-tools${NC}"
                    echo -e "${YELLOW}CentOS/RHEL: sudo yum install bluez bluez-tools${NC}"
                fi
                return 1
            fi
        else
            echo -e "${CYAN}Install manually:${NC}"
            if [ "$os_type" = "Darwin" ]; then
                echo -e "${YELLOW}macOS: brew install blueutil${NC}"
            else
                echo -e "${YELLOW}Ubuntu/Debian: sudo apt install bluetooth bluez-tools${NC}"
                echo -e "${YELLOW}CentOS/RHEL: sudo yum install bluez bluez-tools${NC}"
            fi
            return 1
        fi
    fi
    
    return 0
}

# Function to enable Bluetooth
enable_bluetooth() {
    echo -e "${BLUE}📡 Checking Bluetooth status...${NC}"
    
    local os_type=$(uname)
    
    # For Linux systems
    if [ "$os_type" != "Darwin" ]; then
        # Check and start bluetooth service
        if command -v systemctl >/dev/null 2>&1; then
            echo -e "${BLUE}🔧 Checking bluetooth service...${NC}"
            if ! systemctl is-active --quiet bluetooth; then
                echo -e "${YELLOW}🔌 Starting bluetooth service...${NC}"
                sudo systemctl start bluetooth
                sleep 2
            fi
            
            if ! systemctl is-enabled --quiet bluetooth; then
                echo -e "${YELLOW}⚙️ Enabling bluetooth autostart...${NC}"
                sudo systemctl enable bluetooth
            fi
        fi
        
        # Check rfkill
        if command -v rfkill >/dev/null 2>&1; then
            echo -e "${BLUE}🔍 Checking rfkill blocks...${NC}"
            if rfkill list bluetooth | grep -q "Soft blocked: yes"; then
                echo -e "${YELLOW}🔓 Removing software block on Bluetooth...${NC}"
                sudo rfkill unblock bluetooth
                sleep 2
            fi
            if rfkill list bluetooth | grep -q "Hard blocked: yes"; then
                echo -e "${RED}❌ Bluetooth is hardware blocked (check switch)${NC}"
                return 1
            fi
        fi
    fi
    
    # Check bluetoothctl
    if command -v bluetoothctl >/dev/null 2>&1; then
        echo -e "${BLUE}🔌 Configuring Bluetooth adapter...${NC}"
        
        # Enable adapter and configure
        (
            echo "power on"
            sleep 2
            echo "agent on"
            echo "default-agent"
            echo "discoverable on"
            echo "pairable on"
            sleep 1
            echo "quit"
        ) | bluetoothctl >/dev/null 2>&1
        
        sleep 2
        
        # Check status
        local bt_status=$(echo "show" | bluetoothctl 2>/dev/null | grep "Powered:" | awk '{print $2}')
        if [ "$bt_status" = "yes" ]; then
            echo -e "${GREEN}✅ Bluetooth adapter enabled${NC}"
        else
            echo -e "${YELLOW}⚠️ Failed to enable Bluetooth adapter${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✅ Bluetooth ready for scanning${NC}"
    return 0
}

# Function to scan for Bluetooth devices
scan_bluetooth_devices() {
    echo -e "${BLUE}🔍 Scanning for Bluetooth devices...${NC}"
    echo -e "${YELLOW}Turn on your BT13 remote (long press middle button)${NC}"
    echo -e "${CYAN}Scanning will take 15 seconds...${NC}"
    echo ""
    
    local devices_file="/tmp/bt_devices.txt"
    > "$devices_file"
    
    # Determine OS
    local os_type=$(uname)
    
    # macOS - use blueutil if available
    if [ "$os_type" = "Darwin" ] && command -v blueutil >/dev/null 2>&1; then
        echo -e "${BLUE}🍎 Using blueutil for macOS...${NC}"
        
        # Enable Bluetooth if disabled
        if [ "$(blueutil -p)" = "0" ]; then
            echo -e "${YELLOW}🔌 Enabling Bluetooth...${NC}"
            blueutil -p 1
            sleep 3
        fi
        
        # Scan for devices
        blueutil --inquiry 15 2>/dev/null | while read -r line; do
            if [[ "$line" =~ address:\ ([0-9a-fA-F:]+),\ name:\ \"(.*)\" ]]; then
                local mac="${BASH_REMATCH[1]}"
                local name="${BASH_REMATCH[2]}"
                echo "$mac|$name" >> "$devices_file"
            fi
        done
        
    # Use bluetoothctl if available
    elif command -v bluetoothctl >/dev/null 2>&1; then
        echo -e "${BLUE}🐧 Using bluetoothctl...${NC}"
        
        # Clear device cache
        echo -e "${CYAN}Clearing device cache...${NC}"
        echo "remove *" | bluetoothctl >/dev/null 2>&1
        sleep 1
        
        # Start scanning
        echo -e "${CYAN}Starting scan for 15 seconds...${NC}"
        
        # Create temporary script for bluetoothctl
        local bt_script="/tmp/bt_scan.sh"
        cat > "$bt_script" << 'EOF'
#!/bin/bash
{
    echo "scan on"
    sleep 15
    echo "scan off"
    sleep 1
    echo "devices"
    echo "quit"
} | bluetoothctl
EOF
        chmod +x "$bt_script"
        
        # Run scanning and save all output
        local bt_output="/tmp/bt_output.txt"
        "$bt_script" > "$bt_output" 2>/dev/null
        
        # Remove temporary file
        rm -f "$bt_script"
        
        # Parse result more carefully
        if [ -f "$bt_output" ]; then
            # Look for device lines, excluding service information
            grep "^Device" "$bt_output" | while read -r line; do
                # Extract MAC address (second word)
                local mac=$(echo "$line" | awk '{print $2}')
                
                # Check if it's really a MAC address
                if [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                    # Extract device name (everything after MAC address, remove service tags)
                    local name=$(echo "$line" | sed "s/^Device $mac //" | sed 's/\[[^]]*\]//g' | sed 's/^ *//' | sed 's/ *$//')
                    
                    # If name is empty, use "Unknown Device"
                    if [ -z "$name" ]; then
                        name="Unknown Device"
                    fi
                    
                    # Add device to list
                    echo "$mac|$name" >> "$devices_file"
                fi
            done
            
            rm -f "$bt_output"
        fi
        
    # Use hcitool as fallback
    elif command -v hcitool >/dev/null 2>&1; then
        echo -e "${YELLOW}🔧 Using hcitool for scanning...${NC}"
        timeout 15 hcitool scan 2>/dev/null | grep -E "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" | while read -r mac name; do
            if [ -n "$mac" ]; then
                echo "$mac|${name:-Unknown Device}" >> "$devices_file"
            fi
        done
    else
        echo -e "${RED}❌ Bluetooth tools unavailable${NC}"
        return 1
    fi
    
    # Wait for file write completion
    sleep 2
    
    # Check results
    if [ ! -s "$devices_file" ]; then
        echo -e "${YELLOW}⚠️  No devices found${NC}"
        echo ""
        echo -e "${BLUE}🔍 Bluetooth diagnostics:${NC}"
        
        # Show Bluetooth status
        if command -v bluetoothctl >/dev/null 2>&1; then
            local bt_status=$(echo "show" | bluetoothctl 2>/dev/null | grep "Powered:" | awk '{print $2}')
            echo -e "${CYAN}• Bluetooth adapter: ${bt_status:-unknown}${NC}"
            
            local scanning=$(echo "show" | bluetoothctl 2>/dev/null | grep "Discovering:" | awk '{print $2}')
            echo -e "${CYAN}• Scanning: ${scanning:-unknown}${NC}"
        fi
        
        # Show rfkill status
        if command -v rfkill >/dev/null 2>&1; then
            echo -e "${CYAN}• rfkill status:${NC}"
            rfkill list bluetooth | head -3
        fi
        
        echo ""
        echo -e "${CYAN}Make sure that:${NC}"
        echo -e "${CYAN}1. BT13 is blinking red+blue (pairing mode)${NC}"
        echo -e "${CYAN}2. BT13 is nearby (< 5 meters)${NC}"
        echo -e "${CYAN}3. BT13 is not connected to another device${NC}"
        echo -e "${CYAN}4. Bluetooth is enabled in system${NC}"
        echo ""
        echo -e "${BLUE}💡 Try:${NC}"
        echo -e "${CYAN}• Restart BT13 (turn off/on)${NC}"
        echo -e "${CYAN}• Disconnect BT13 from phone/computer${NC}"
        echo -e "${CYAN}• Run: sudo systemctl restart bluetooth${NC}"
        echo -e "${CYAN}• Run script with sudo${NC}"
        return 1
    fi
    
    return 0
}

# Function for manual MAC address input
manual_mac_input() {
    echo -e "${BLUE}✏️  Manual MAC address input${NC}"
    echo -e "${CYAN}Enter your BT13 remote MAC address in format XX:XX:XX:XX:XX:XX${NC}"
    echo -e "${YELLOW}Example: 8B:EB:75:4E:65:97${NC}"
    echo ""
    
    while true; do
        read -p "MAC address: " manual_mac
        
        # Check MAC address format
        if [[ "$manual_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            echo -e "${GREEN}✅ MAC address is correct: $manual_mac${NC}"
            echo "$manual_mac" > /tmp/selected_mac.txt
            return 0
        else
            echo -e "${RED}❌ Invalid MAC address format${NC}"
            echo -e "${CYAN}Use format: XX:XX:XX:XX:XX:XX (example: 8B:EB:75:4E:65:97)${NC}"
            echo ""
        fi
    done
}

# Function to select device
select_bluetooth_device() {
    local devices_file="/tmp/bt_devices.txt"
    
    echo -e "${GREEN}✅ Found Bluetooth devices:${NC}"
    echo ""
    
    local devices=()
    local i=1
    
    while IFS='|' read -r mac name; do
        # Check that MAC address has correct format
        if [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] && [ -n "$name" ]; then
            devices+=("$mac|$name")
            echo -e "${CYAN}$i) $name ${YELLOW}($mac)${NC}"
            ((i++))
        fi
    done < "$devices_file"
    
    echo ""
    echo -e "${CYAN}$((${#devices[@]}+1))) Enter MAC address manually${NC}"
    echo -e "${CYAN}0) Skip and use default MAC${NC}"
    echo ""
    
    while true; do
        read -p "Select device (0-$((${#devices[@]}+1))): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$((${#devices[@]}+1))" ]; then
            if [ "$choice" -eq 0 ]; then
                echo -e "${YELLOW}⚠️  Using default MAC${NC}"
                return 1
            elif [ "$choice" -eq "$((${#devices[@]}+1))" ]; then
                return $(manual_mac_input && echo 0 || echo 1)
            else
                local selected_device="${devices[$((choice-1))]}"
                local selected_mac=$(echo "$selected_device" | cut -d'|' -f1)
                local selected_name=$(echo "$selected_device" | cut -d'|' -f2)
                
                # Additional MAC address check
                if [[ "$selected_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                    echo -e "${GREEN}✅ Selected: $selected_name ($selected_mac)${NC}"
                    echo "$selected_mac" > /tmp/selected_mac.txt
                    return 0
                else
                    echo -e "${RED}❌ Invalid MAC address format: $selected_mac${NC}"
                    echo -e "${CYAN}Try selecting another device or enter MAC manually${NC}"
                fi
            fi
        else
            echo -e "${RED}❌ Invalid choice. Enter number from 0 to $((${#devices[@]}+1))${NC}"
        fi
    done
}

# Function to update MAC address in code
update_mac_in_code() {
    local new_mac="$1"
    
    echo -e "${BLUE}🔧 Updating MAC address in code...${NC}"
    
    if [ ! -f "$MAIN_C_FILE" ]; then
        echo -e "${RED}❌ main.c file not found: $MAIN_C_FILE${NC}"
        return 1
    fi
    
    # Check MAC address format
    if ! [[ "$new_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        echo -e "${RED}❌ Invalid MAC address format: $new_mac${NC}"
        return 1
    fi
    
    # Convert MAC address to array format
    local mac_array=""
    IFS=':' read -ra MAC_PARTS <<< "$new_mac"
    for part in "${MAC_PARTS[@]}"; do
        if [ -z "$mac_array" ]; then
            mac_array="0x$part"
        else
            mac_array="$mac_array, 0x$part"
        fi
    done
    mac_array="{$mac_array}"
    
    echo -e "${CYAN}Converted MAC: $mac_array${NC}"
    
    # Create backup
    cp "$MAIN_C_FILE" "$MAIN_C_FILE.backup"
    
    # Update MAC address in code
    if sed -i.tmp "s/uint8_t target_mac\[6\] = {[^}]*}/uint8_t target_mac[6] = $mac_array/" "$MAIN_C_FILE"; then
        rm -f "$MAIN_C_FILE.tmp"
        echo -e "${GREEN}✅ MAC address updated in code: $mac_array${NC}"
        echo -e "${GREEN}💾 Backup created: $MAIN_C_FILE.backup${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to update MAC address${NC}"
        # Restore from backup
        mv "$MAIN_C_FILE.backup" "$MAIN_C_FILE"
        return 1
    fi
}

# Function for Bluetooth scanning and setup
bluetooth_setup() {
    echo -e "${BLUE}📡 Setting up Bluetooth device${NC}"
    echo ""
    
    # Check tools
    if ! check_bluetooth_tools; then
        echo -e "${YELLOW}⚠️  Bluetooth tools unavailable${NC}"
        echo ""
        echo -e "${BLUE}💡 Would you like to enter MAC address manually?${NC}"
        read -p "Enter MAC manually? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if manual_mac_input; then
                local selected_mac=$(cat /tmp/selected_mac.txt)
                if update_mac_in_code "$selected_mac"; then
                    echo -e "${GREEN}🎉 MAC address configured manually!${NC}"
                    return 0
                fi
            fi
        fi
        return 1
    fi
    
    # Enable Bluetooth
    if ! enable_bluetooth; then
        echo -e "${YELLOW}⚠️  Failed to enable Bluetooth${NC}"
        echo ""
        echo -e "${BLUE}💡 Would you like to enter MAC address manually?${NC}"
        read -p "Enter MAC manually? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if manual_mac_input; then
                local selected_mac=$(cat /tmp/selected_mac.txt)
                if update_mac_in_code "$selected_mac"; then
                    echo -e "${GREEN}🎉 MAC address configured manually!${NC}"
                    return 0
                fi
            fi
        fi
        return 1
    fi
    
    # Scan for devices
    if ! scan_bluetooth_devices; then
        echo -e "${YELLOW}⚠️  Scanning yielded no results${NC}"
        echo ""
        echo -e "${BLUE}💡 Would you like to enter MAC address manually?${NC}"
        read -p "Enter MAC manually? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if manual_mac_input; then
                local selected_mac=$(cat /tmp/selected_mac.txt)
                if update_mac_in_code "$selected_mac"; then
                    echo -e "${GREEN}🎉 MAC address configured manually!${NC}"
                    return 0
                fi
            fi
        fi
        return 1
    fi
    
    # Select device
    if select_bluetooth_device; then
        local selected_mac=$(cat /tmp/selected_mac.txt)
        if update_mac_in_code "$selected_mac"; then
            echo -e "${GREEN}🎉 Bluetooth device configured successfully!${NC}"
            return 0
        fi
    else
        echo -e "${YELLOW}⚠️  Using default MAC address${NC}"
        return 0
    fi
    
    return 1
}

# Function to check ESP-IDF installation
check_esp_idf() {
    if [ -d "$ESP_IDF_PATH" ]; then
        cd "$ESP_IDF_PATH"
        local current_version=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
        echo -e "${GREEN}✅ ESP-IDF found: $current_version${NC}"
        
        # Check if update is needed
        git fetch --tags >/dev/null 2>&1
        if ! git describe --tags --exact-match >/dev/null 2>&1 || [ "$(git describe --tags --exact-match)" != "$ESP_IDF_VERSION" ]; then
            echo -e "${YELLOW}⚠️  Stable version $ESP_IDF_VERSION available${NC}"
            return 1
        else
            echo -e "${GREEN}✅ Current stable version installed${NC}"
            return 0
        fi
    else
        echo -e "${RED}❌ ESP-IDF not found${NC}"
        return 1
    fi
}

# Function to install ESP-IDF
install_esp_idf() {
    echo -e "${BLUE}📦 Installing ESP-IDF $ESP_IDF_VERSION...${NC}"
    
    # Create directory
    mkdir -p "$ESP_DIR"
    cd "$ESP_DIR"
    
    # Remove old version if exists
    if [ -d "esp-idf" ]; then
        echo -e "${YELLOW}🗑️  Removing old version...${NC}"
        rm -rf esp-idf
    fi
    
    # Clone stable version
    echo -e "${BLUE}📥 Cloning ESP-IDF $ESP_IDF_VERSION...${NC}"
    git clone --recursive --branch $ESP_IDF_VERSION https://github.com/espressif/esp-idf.git
    
    cd esp-idf
    
    # Install tools
    echo -e "${BLUE}🔧 Installing tools...${NC}"
    ./install.sh esp32
    
    echo -e "${GREEN}✅ ESP-IDF $ESP_IDF_VERSION installed successfully!${NC}"
}

# Function to update ESP-IDF
update_esp_idf() {
    echo -e "${BLUE}🔄 Updating ESP-IDF to $ESP_IDF_VERSION...${NC}"
    
    cd "$ESP_IDF_PATH"
    git fetch --tags
    git checkout $ESP_IDF_VERSION
    git submodule update --init --recursive
    
    # Reinstall tools
    echo -e "${BLUE}🔧 Updating tools...${NC}"
    ./install.sh esp32
    
    echo -e "${GREEN}✅ ESP-IDF updated to $ESP_IDF_VERSION!${NC}"
}

# Function to build project
build_project() {
    echo -e "${BLUE}🔨 Building project...${NC}"
    
    cd "$PROJECT_DIR"
    
    # Clean previous build
    if [ -d "build" ]; then
        rm -rf build
    fi
    
    # Set target and build
    idf.py set-target esp32
    idf.py build
    
    echo -e "${GREEN}✅ Project built successfully!${NC}"
}

# Function to flash ESP32 and run monitor
flash_and_monitor() {
    echo -e "${BLUE}⚡ Looking for ESP32...${NC}"
    
    # Look for available ports
    local ports=()
    for port in /dev/ttyUSB* /dev/ttyACM* /dev/cu.usbserial* /dev/cu.SLAB_USBtoUART*; do
        if [ -e "$port" ]; then
            ports+=("$port")
        fi
    done
    
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${RED}❌ ESP32 not found. Connect device and try again.${NC}"
        return 1
    fi
    
    # Select port
    local selected_port
    if [ ${#ports[@]} -eq 1 ]; then
        selected_port="${ports[0]}"
        echo -e "${GREEN}✅ Found ESP32 on port: $selected_port${NC}"
    else
        echo -e "${YELLOW}Found multiple ports:${NC}"
        for i in "${!ports[@]}"; do
            echo -e "${CYAN}$((i+1))) ${ports[i]}${NC}"
        done
        read -p "Select port (1-${#ports[@]}): " choice
        selected_port="${ports[$((choice-1))]}"
    fi
    
    # Flash and run monitor in one command
    echo -e "${BLUE}⚡ Flashing ESP32 on $selected_port at speed $FLASH_SPEED and starting monitor...${NC}"
    echo -e "${YELLOW}Press Ctrl+] to exit monitor${NC}"
    echo ""
    
    cd "$PROJECT_DIR"
    
    # Run flash and monitor in one command
    idf.py -p "$selected_port" -b "$FLASH_SPEED" flash monitor | tee /tmp/esp32_monitor.log
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Flashing and monitoring completed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Flashing or monitoring error!${NC}"
        return 1
    fi
}

# Function to analyze monitor logs
analyze_monitor_logs() {
    echo -e "${BLUE}📊 Analyzing connection logs...${NC}"
    
    # Check log for successful connection
    if grep -q "BT13\|bluetooth\|connected\|ready\|Found device\|HID" /tmp/esp32_monitor.log 2>/dev/null; then
        echo -e "${GREEN}✅ BT13 activity detected in logs!${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  BT13 connection not detected in logs${NC}"
        echo -e "${BLUE}For repeated monitoring run:${NC}"
        echo -e "${YELLOW}idf.py monitor${NC}"
        return 1
    fi
}

# Function to offer ESP-IDF cleanup
offer_cleanup() {
    echo ""
    echo -e "${YELLOW}🧹 Would you like to remove ESP-IDF to save space?${NC}"
    echo -e "${CYAN}ESP-IDF takes about 2GB of disk space${NC}"
    echo ""
    read -p "Remove ESP-IDF? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}🗑️  Removing ESP-IDF...${NC}"
        rm -rf "$ESP_DIR"
        echo -e "${GREEN}✅ ESP-IDF removed${NC}"
    else
        echo -e "${GREEN}✅ ESP-IDF kept in $ESP_DIR${NC}"
        echo -e "${BLUE}For reuse run:${NC}"
        echo -e "${YELLOW}source $ESP_IDF_PATH/export.sh${NC}"
    fi
}

# Main function
main() {
    print_header
    
    # Check system dependencies
    echo ""
    if ! check_system_dependencies; then
        echo -e "${RED}❌ Failed to install system dependencies${NC}"
        echo -e "${YELLOW}Install them manually and run the script again${NC}"
        exit 1
    fi
    
    # Check ESP-IDF
    echo ""
    if check_esp_idf; then
        echo -e "${GREEN}✅ ESP-IDF is up to date${NC}"
    else
        echo -e "${YELLOW}🔄 ESP-IDF installation/update required${NC}"
        read -p "Continue? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            if [ -d "$ESP_IDF_PATH" ]; then
                update_esp_idf
            else
                install_esp_idf
            fi
        else
            echo -e "${YELLOW}⚠️  Installation cancelled${NC}"
            exit 0
        fi
    fi
    
    # Setup Bluetooth device
    echo ""
    bluetooth_setup
    
    # Activate ESP-IDF once for all subsequent operations
    echo ""
    echo -e "${BLUE}🔧 Activating ESP-IDF environment...${NC}"
    cd "$PROJECT_DIR"
    source "$ESP_IDF_PATH/export.sh"
    
    # Build project
    echo ""
    build_project
    
    # Flash ESP32 and run monitor
    echo ""
    if flash_and_monitor; then
        # Analyze logs
        echo ""
        if analyze_monitor_logs; then
            echo -e "${GREEN}🎉 Installation completed successfully!${NC}"
            offer_cleanup
        else
            echo -e "${YELLOW}⚠️  Project flashed, but BT13 connection needs verification${NC}"
        fi
    else
        echo -e "${RED}❌ Flashing error. Check ESP32 connection${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}✅ Done!${NC}"
}

# Run main function
main "$@"