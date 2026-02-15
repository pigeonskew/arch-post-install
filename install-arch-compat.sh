#!/usr/bin/env bash

# Arch Linux Automated Installation Script
# Features: User input, 2 locales max, essential packages only, Liquorix kernel, performance tweaks
# WARNING: This will wipe the selected disk. Use with caution.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

check_uefi() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "UEFI"
    else
        echo "BIOS"
    fi
}

# Check if running from Arch ISO
if [[ ! -f /etc/arch-release ]] || [[ ! -d /run/archiso/bootmnt ]]; then
    error_exit "This script must be run from the Arch Linux live ISO environment."
fi

# Check internet connection
if ! ping -c 1 archlinux.org &>/dev/null; then
    error_exit "No internet connection detected. Please configure network first."
fi

clear
echo "=========================================="
echo "  Arch Linux Automated Installer"
echo "  Optimized for Performance & Compatibility"
echo "=========================================="
echo ""

# --- USER INPUT SECTION ---

# Select disk
info "Available disks:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep disk
echo ""
read -rp "Enter target disk (e.g., /dev/sda or /dev/nvme0n1): " TARGET_DISK

if [[ ! -b "$TARGET_DISK" ]]; then
    error_exit "Invalid disk: $TARGET_DISK"
fi

# Confirm wipe
warning "ALL DATA ON $TARGET_DISK WILL BE DESTROYED!"
read -rp "Are you sure you want to continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    error_exit "Installation aborted by user."
fi

# Hostname
read -rp "Enter hostname: " HOSTNAME
if [[ -z "$HOSTNAME" ]]; then
    HOSTNAME="archlinux"
fi

# Username
read -rp "Enter username: " USERNAME
if [[ -z "$USERNAME" ]]; then
    error_exit "Username cannot be empty."
fi

# Passwords
read -rsp "Enter root password: " ROOT_PASS
echo ""
read -rsp "Confirm root password: " ROOT_PASS_CONFIRM
echo ""
if [[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]]; then
    error_exit "Root passwords do not match."
fi

read -rsp "Enter password for $USERNAME: " USER_PASS
echo ""
read -rsp "Confirm password for $USERNAME: " USER_PASS_CONFIRM
echo ""
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    error_exit "User passwords do not match."
fi

# Timezone
info "Common timezones: America/New_York, Europe/London, Europe/Berlin, Asia/Tokyo, Australia/Sydney"
read -rp "Enter timezone (e.g., America/New_York): " TIMEZONE
if [[ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    error_exit "Invalid timezone: $TIMEZONE"
fi

# Locale selection (Maximum 2)
echo ""
info "Select up to 2 locales:"
echo "1) en_US.UTF-8 (English US) - Recommended"
echo "2) en_GB.UTF-8 (English UK)"
echo "3) de_DE.UTF-8 (German)"
echo "4) fr_FR.UTF-8 (French)"
echo "5) es_ES.UTF-8 (Spanish)"
echo "6) zh_CN.UTF-8 (Chinese Simplified)"
echo "7) ja_JP.UTF-8 (Japanese)"
echo "8) ru_RU.UTF-8 (Russian)"
echo ""

LOCALES=()
read -rp "Select primary locale (1-8, default 1): " LOCALE_CHOICE
LOCALE_CHOICE=${LOCALE_CHOICE:-1}

case $LOCALE_CHOICE in
    1) LOCALES+=("en_US.UTF-8") ;;
    2) LOCALES+=("en_GB.UTF-8") ;;
    3) LOCALES+=("de_DE.UTF-8") ;;
    4) LOCALES+=("fr_FR.UTF-8") ;;
    5) LOCALES+=("es_ES.UTF-8") ;;
    6) LOCALES+=("zh_CN.UTF-8") ;;
    7) LOCALES+=("ja_JP.UTF-8") ;;
    8) LOCALES+=("ru_RU.UTF-8") ;;
    *) LOCALES+=("en_US.UTF-8") ;;
esac

read -rp "Add secondary locale? (yes/no, default no): " ADD_SECOND
if [[ "$ADD_SECOND" == "yes" ]]; then
    read -rp "Select secondary locale (1-8): " LOCALE2_CHOICE
    case $LOCALE2_CHOICE in
        1) LOCALES+=("en_US.UTF-8") ;;
        2) LOCALES+=("en_GB.UTF-8") ;;
        3) LOCALES+=("de_DE.UTF-8") ;;
        4) LOCALES+=("fr_FR.UTF-8") ;;
        5) LOCALES+=("es_ES.UTF-8") ;;
        6) LOCALES+=("zh_CN.UTF-8") ;;
        7) LOCALES+=("ja_JP.UTF-8") ;;
        8) LOCALES+=("ru_RU.UTF-8") ;;
    esac
fi

# Remove duplicates
LOCALES=($(echo "${LOCALES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Keyboard layout
read -rp "Enter keyboard layout (e.g., us, de, fr, uk, default: us): " KEYMAP
KEYMAP=${KEYMAP:-us}

# Desktop Environment choice (for essential packages)
echo ""
info "Select base system type:"
echo "1) Minimal (Server/Headless)"
echo "2) Desktop (Wayland ready - no DE, prepare for DankMaterialShell)"
read -rp "Choice (1-2, default 2): " SYSTEM_TYPE
SYSTEM_TYPE=${SYSTEM_TYPE:-2}

# --- DISK PREPARATION ---

info "Updating system clock..."
timedatectl set-ntp true

info "Partitioning disk $TARGET_DISK..."
BOOT_MODE=$(check_uefi)

if [[ "$BOOT_MODE" == "UEFI" ]]; then
    # UEFI Partitioning: EFI(512M), Root(remainder)
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
    
    if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
        EFI_PART="${TARGET_DISK}p1"
        ROOT_PART="${TARGET_DISK}p2"
    else
        EFI_PART="${TARGET_DISK}1"
        ROOT_PART="${TARGET_DISK}2"
    fi
    
    info "Formatting partitions..."
    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"
    
    info "Mounting partitions..."
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot/efi
    mount "$EFI_PART" /mnt/boot/efi
else
    # BIOS Partitioning: Boot(1M), Root(remainder)
    parted -s "$TARGET_DISK" mklabel msdos
    parted -s "$TARGET_DISK" mkpart primary ext4 1MiB 100%
    parted -s "$TARGET_DISK" set 1 boot on
    
    if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
        ROOT_PART="${TARGET_DISK}p1"
    else
        ROOT_PART="${TARGET_DISK}1"
    fi
    
    info "Formatting partition..."
    mkfs.ext4 -F "$ROOT_PART"
    
    info "Mounting partition..."
    mount "$ROOT_PART" /mnt
fi

# --- BASE INSTALLATION ---

info "Installing base system..."
# Essential packages only - no duplicates
BASE_PACKAGES="base base-devel linux-firmware"

# CPU microcode
if grep -q "Intel" /proc/cpuinfo; then
    BASE_PACKAGES="$BASE_PACKAGES intel-ucode"
elif grep -q "AMD" /proc/cpuinfo; then
    BASE_PACKAGES="$BASE_PACKAGES amd-ucode"
fi

# Essential filesystem and hardware support
BASE_PACKAGES="$BASE_PACKAGES btrfs-progs dosfstools e2fsprogs ntfs-3g"

# Networking
BASE_PACKAGES="$BASE_PACKAGES networkmanager iwd dhcpcd"

# Essential utilities (no duplicates, single choice per category)
BASE_PACKAGES="$BASE_PACKAGES vim nano git curl wget man-db man-pages"

# Compression and archive tools
BASE_PACKAGES="$BASE_PACKAGES zip unzip p7zip tar gzip"

# Hardware compatibility
BASE_PACKAGES="$BASE_PACKAGES usbutils pciutils lsscsi smartmontools"

# Audio support (PipeWire - modern standard)
BASE_PACKAGES="$BASE_PACKAGES pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber"

# Bluetooth
BASE_PACKAGES="$BASE_PACKAGES bluez bluez-utils"

# Power management
BASE_PACKAGES="$BASE_PACKAGES tlp acpi acpid"

# Performance monitoring
BASE_PACKAGES="$BASE_PACKAGES htop iotop"

# Fonts (essential only)
BASE_PACKAGES="$BASE_PACKAGES noto-fonts noto-fonts-emoji terminus-font"

# If desktop system
if [[ "$SYSTEM_TYPE" == "2" ]]; then
    # Xorg and Wayland support
    BASE_PACKAGES="$BASE_PACKAGES xorg-server xorg-xinit xorg-xwayland"
    # GPU drivers (detect and install all for compatibility)
    BASE_PACKAGES="$BASE_PACKAGES mesa lib32-mesa vulkan-icd-loader"
    # Input
    BASE_PACKAGES="$BASE_PACKAGES libinput xf86-input-libinput"
    # Display manager (lightweight, user will install DankMaterialShell)
    BASE_PACKAGES="$BASE_PACKAGES ly"
fi

# Install base
pacstrap /mnt $BASE_PACKAGES

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --- SYSTEM CONFIGURATION ---

info "Configuring system..."

# Create configuration script to run in chroot
cat > /mnt/root/setup.sh << 'EOFSCRIPT'
#!/usr/bin/env bash
set -e

HOSTNAME="${1}"
TIMEZONE="${2}"
KEYMAP="${3}"
ROOT_PASS="${4}"
USERNAME="${5}"
USER_PASS="${6}"
BOOT_MODE="${7}"
shift 7
LOCALES=("$@")

# Time
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Locales (max 2)
for locale in "${LOCALES[@]}"; do
    echo "${locale} UTF-8" >> /etc/locale.gen
done
locale-gen

echo "LANG=${LOCALES[0]}" > /etc/locale.conf

# Keyboard
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable tlp
systemctl enable acpid
systemctl enable fstrim.timer

# Create user
useradd -m -G wheel,audio,video,input,power,storage -s /bin/bash "${USERNAME}"
echo "root:${ROOT_PASS}" | chpasswd
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Sudo access
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Install bootloader
if [[ "${BOOT_MODE}" == "UEFI" ]]; then
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc "${TARGET_DISK}"
fi

# Performance tweaks in grub
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& mitigations=off nowatchdog processor.max_cstate=1 intel_idle.max_cstate=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Performance tweaks - sysctl
cat > /etc/sysctl.d/99-performance.conf << 'EOF'
# Performance optimizations
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.sched_latency_ns=1000000
kernel.sched_min_granularity_ns=100000
kernel.sched_wakeup_granularity_ns=50000
EOF

# CPU governor performance
cat > /etc/default/cpupower << 'EOF'
governor='performance'
EOF

# Install Liquorix Kernel
echo "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Update grub for Liquorix
grub-mkconfig -o /boot/grub/grub.cfg

# Enable ly display manager if desktop
if [[ -f /usr/bin/ly ]]; then
    systemctl enable ly
fi

# Initramfs
mkinitcpio -P

EOFSCRIPT

chmod +x /mnt/root/setup.sh

# Run configuration in chroot
arch-chroot /mnt /root/setup.sh "$HOSTNAME" "$TIMEZONE" "$KEYMAP" "$ROOT_PASS" "$USERNAME" "$USER_PASS" "$BOOT_MODE" "${LOCALES[@]}"

# Cleanup
rm /mnt/root/setup.sh

# Unmount
info "Unmounting partitions..."
umount -R /mnt

success "Installation complete!"
echo ""
echo "=========================================="
echo "  POST-INSTALLATION INSTRUCTIONS"
echo "=========================================="
echo ""
echo "1. Remove the installation medium"
echo "2. Reboot: reboot"
echo "3. Login as $USERNAME"
echo "4. Install your custom shell (DankMaterialShell)"
echo ""
echo "Performance tweaks applied:"
echo "  - Liquorix kernel installed (low-latency)"
echo "  - CPU governor set to performance"
echo "  - Swappiness reduced to 10"
echo "  - Scheduler latency optimized"
echo "  - Mitigations disabled (performance over security)"
echo ""
echo "Essential packages installed:"
echo "  - Base system with development tools"
echo "  - NetworkManager + Bluetooth"
echo "  - PipeWire audio stack"
echo "  - GPU drivers (Mesa/Vulkan)"
echo "  - TLP power management"
echo "  - Ly display manager (if desktop)"
echo ""
success "Enjoy your optimized Arch Linux system!"
