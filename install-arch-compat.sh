#!/bin/bash

# Arch Linux Automated Installation Script
# This script must be run as root from the Arch ISO

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Check if running from Arch ISO
if [ ! -f /etc/arch-release ]; then
    print_error "This script must be run from Arch Linux ISO"
    exit 1
fi

# Welcome message
clear
print_status "Welcome to Arch Linux Automated Installer"
print_status "This script will guide you through installing Arch Linux"
echo ""

# User input for configuration
print_status "Please provide the following information:"

# Hostname
read -p "Enter hostname [archlinux]: " HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}

# Username
read -p "Enter username: " USERNAME
while [ -z "$USERNAME" ]; do
    print_error "Username cannot be empty"
    read -p "Enter username: " USERNAME
done

# Password
read -s -p "Enter password for $USERNAME: " PASSWORD
echo ""
read -s -p "Confirm password: " PASSWORD_CONFIRM
echo ""
while [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; do
    print_error "Passwords do not match"
    read -s -p "Enter password for $USERNAME: " PASSWORD
    echo ""
    read -s -p "Confirm password: " PASSWORD_CONFIRM
    echo ""
done

# Root password
read -s -p "Enter root password: " ROOT_PASSWORD
echo ""
read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
echo ""
while [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; do
    print_error "Passwords do not match"
    read -s -p "Enter root password: " ROOT_PASSWORD
    echo ""
    read -s -p "Confirm root password: " ROOT_PASSWORD_CONFIRM
    echo ""
done

# Locale selection
print_status "Select locale (enter number):"
echo "1) en_US.UTF-8 (US English)"
echo "2) en_GB.UTF-8 (British English)"
echo "3) es_ES.UTF-8 (Spanish)"
echo "4) de_DE.UTF-8 (German)"
echo "5) fr_FR.UTF-8 (French)"
echo "6) Custom"
read -p "Choice [1]: " LOCALE_CHOICE
LOCALE_CHOICE=${LOCALE_CHOICE:-1}

case $LOCALE_CHOICE in
    1) LOCALE1="en_US.UTF-8" ;;
    2) LOCALE1="en_GB.UTF-8" ;;
    3) LOCALE1="es_ES.UTF-8" ;;
    4) LOCALE1="de_DE.UTF-8" ;;
    5) LOCALE1="fr_FR.UTF-8" ;;
    6) read -p "Enter first locale: " LOCALE1 ;;
    *) LOCALE1="en_US.UTF-8" ;;
esac

print_status "Select second locale (optional, press enter to skip):"
echo "1) en_US.UTF-8 (US English)"
echo "2) en_GB.UTF-8 (British English)"
echo "3) es_ES.UTF-8 (Spanish)"
echo "4) de_DE.UTF-8 (German)"
echo "5) fr_FR.UTF-8 (French)"
echo "6) Custom"
echo "7) Skip"
read -p "Choice [7]: " LOCALE2_CHOICE
LOCALE2_CHOICE=${LOCALE2_CHOICE:-7}

case $LOCALE2_CHOICE in
    1) LOCALE2="en_US.UTF-8" ;;
    2) LOCALE2="en_GB.UTF-8" ;;
    3) LOCALE2="es_ES.UTF-8" ;;
    4) LOCALE2="de_DE.UTF-8" ;;
    5) LOCALE2="fr_FR.UTF-8" ;;
    6) read -p "Enter second locale: " LOCALE2 ;;
    7) LOCALE2="" ;;
    *) LOCALE2="" ;;
esac

# Disk selection
print_status "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Enter disk to install Arch on (e.g., sda, nvme0n1): " DISK
DISK="/dev/$DISK"
while [ ! -b "$DISK" ]; do
    print_error "Disk $DISK not found"
    read -p "Enter disk to install Arch on: " DISK
    DISK="/dev/$DISK"
done

# Confirm destructive action
print_warning "This will ERASE ALL DATA on $DISK"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    print_error "Installation cancelled"
    exit 1
fi

# Start installation
print_status "Starting Arch Linux installation..."

# Update system clock
timedatectl set-ntp true

# Partition the disk
print_status "Partitioning $DISK..."
parted "$DISK" --script mklabel gpt

# Create partitions
if [[ "$DISK" == *"nvme"* ]]; then
    PART_PREFIX="p"
else
    PART_PREFIX=""
fi

# EFI partition (512MB)
parted "$DISK" --script mkpart ESP fat32 1MB 512MB
parted "$DISK" --script set 1 esp on

# Root partition (rest of the disk)
parted "$DISK" --script mkpart primary ext4 512MB 100%

# Format partitions
print_status "Formatting partitions..."
mkfs.fat -F32 "${DISK}${PART_PREFIX}1"
mkfs.ext4 -F "${DISK}${PART_PREFIX}2"

# Mount partitions
print_status "Mounting partitions..."
mount "${DISK}${PART_PREFIX}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}${PART_PREFIX}1" /mnt/boot

# Install base system
print_status "Installing base system..."
pacstrap /mnt base base-devel linux-firmware

# Generate fstab
print_status "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Create a script to run inside chroot
cat > /mnt/chroot_script.sh <<'EOF'
#!/bin/bash

# Enable error handling
set -e

echo "=================================="
echo "Starting chroot configuration..."
echo "=================================="

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Configure locale
echo "$1 UTF-8" >> /etc/locale.gen
if [ -n "$2" ]; then
    echo "$2 UTF-8" >> /etc/locale.gen
fi
locale-gen

echo "LANG=$1" > /etc/locale.conf

# Set hostname
echo "$3" > /etc/hostname

# Set hosts file
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $3.localdomain $3
HOSTS

# Set root password
echo "root:$4" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash $5
echo "$5:$6" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Install and configure bootloader (GRUB)
echo "Installing GRUB..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Optimize pacman configuration
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

# Install Liquorix kernel using the provided curl command
echo "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Update system after kernel installation
pacman -Syu --noconfirm

# Install essential packages in groups with verification
echo "=================================="
echo "Installing essential packages..."
echo "=================================="

# Function to install packages and verify
install_packages() {
    local category=$1
    shift
    echo "Installing $category packages: $@"
    pacman -S --noconfirm "$@"
    if [ $? -eq 0 ]; then
        echo "✓ $category packages installed successfully"
    else
        echo "✗ Failed to install $category packages"
        exit 1
    fi
}

# Install packages by category
install_packages "System Utilities" \
    htop \
    man-db \
    man-pages \
    texinfo \
    networkmanager \
    network-manager-applet \
    openssh \
    reflector \
    git \
    curl \
    wget \
    unzip \
    zip \
    p7zip \
    ntfs-3g \
    dosfstools

install_packages "Video Drivers" \
    xf86-video-intel \
    xf86-video-amdgpu \
    xf86-video-nouveau \
    xf86-video-vesa \
    mesa \
    vulkan-intel \
    vulkan-radeon \
    vulkan-mesa-layer \
    libva-intel-driver \
    libva-mesa-driver \
    intel-media-driver \
    nvidia-utils

install_packages "Audio" \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber

install_packages "Printing" \
    cups \
    cups-pdf

install_packages "Bluetooth" \
    bluez \
    bluez-utils

install_packages "Performance Tools" \
    earlyoom \
    irqbalance \
    tuned \
    cpupower

install_packages "Filesystem Support" \
    btrfs-progs \
    exfatprogs \
    f2fs-tools \
    xfsprogs

install_packages "Development" \
    gcc \
    make \
    pkg-config

# Update GRUB after all installations
grub-mkconfig -o /boot/grub/grub.cfg

echo "=================================="
echo "Verifying installed packages..."
echo "=================================="

# Check if critical packages are installed
check_package() {
    if pacman -Q "$1" &>/dev/null; then
        echo "✓ $1 is installed"
        return 0
    else
        echo "✗ $1 is NOT installed"
        return 1
    fi
}

# Verify critical packages
check_package "networkmanager"
check_package "cups"
check_package "bluez"
check_package "earlyoom"
check_package "irqbalance"
check_package "tuned"

echo "=================================="
echo "Enabling services..."
echo "=================================="

# List all available services for debugging
echo "Available systemd services:"
ls -la /usr/lib/systemd/system/ | grep -E "network|cups|bluetooth|earlyoom|irqbalance|tuned" | head -20

# Enable services with error checking
enable_service() {
    local service=$1
    echo "Attempting to enable $service..."
    
    # Check if service file exists
    if [ -f "/usr/lib/systemd/system/$service" ] || [ -f "/etc/systemd/system/$service" ]; then
        systemctl enable "$service"
        echo "✓ $service enabled"
    elif systemctl list-unit-files | grep -q "^$service"; then
        systemctl enable "$service"
        echo "✓ $service enabled"
    else
        echo "⚠ Service $service not found, searching..."
        # Search for similar service names
        found=$(systemctl list-unit-files | grep -i "${service%.service}" | head -n1 | awk '{print $1}')
        if [ -n "$found" ]; then
            echo "Found similar service: $found"
            systemctl enable "$found"
            echo "✓ $found enabled"
        else
            echo "✗ Could not find $service or similar"
        fi
    fi
}

# Enable core services
enable_service "NetworkManager.service"
enable_service "cups.service"
enable_service "bluetooth.service"
enable_service "earlyoom.service"
enable_service "irqbalance.service"
enable_service "tuned.service"

# Create a list of enabled services
echo "=================================="
echo "Currently enabled services:"
systemctl list-unit-files --state=enabled | grep -E "network|cups|bluetooth|earlyoom|irqbalance|tuned" || echo "No matching services found"
echo "=================================="

# Optimize system performance
cat >> /etc/sysctl.d/99-performance.conf <<SYSCTL
# Increase system limits
vm.max_map_count=1048576
kernel.numa_balancing=0

# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL

# Configure CPU governor for performance
echo 'GOVERNOR="performance"' > /etc/default/cpupower

# Create verification file with installed packages
pacman -Q > /root/installed_packages.txt
systemctl list-unit-files --state=enabled > /root/enabled_services.txt

echo "=================================="
echo "Chroot configuration completed!"
echo "Installed packages saved to /root/installed_packages.txt"
echo "Enabled services saved to /root/enabled_services.txt"
echo "=================================="
EOF

# Make the chroot script executable
chmod +x /mnt/chroot_script.sh

# Chroot and run the configuration script with all parameters
print_status "Entering chroot and configuring system..."
arch-chroot /mnt /bin/bash /chroot_script.sh "$LOCALE1" "$LOCALE2" "$HOSTNAME" "$ROOT_PASSWORD" "$USERNAME" "$PASSWORD"

# Check installation results
print_status "Checking installation results..."

if [ -f "/mnt/root/installed_packages.txt" ]; then
    print_status "Packages installed:"
    echo "----------------------------------------"
    grep -E "networkmanager|cups|bluez|earlyoom|irqbalance|tuned" "/mnt/root/installed_packages.txt" || print_warning "Critical packages not found in installation list"
    echo "----------------------------------------"
else
    print_warning "Package list not found"
fi

if [ -f "/mnt/root/enabled_services.txt" ]; then
    print_status "Services enabled:"
    echo "----------------------------------------"
    cat "/mnt/root/enabled_services.txt"
    echo "----------------------------------------"
fi

# Clean up
rm -f /mnt/chroot_script.sh

# Unmount partitions
print_status "Unmounting partitions..."
umount -R /mnt

print_status "Installation complete!"
print_status "You can now reboot into your new Arch Linux system"

# Final instructions
cat << EOF

${GREEN}=== INSTALLATION COMPLETE ===${NC}

${YELLOW}After first boot:${NC}

1. Check installed packages:
   cat /root/installed_packages.txt

2. Check enabled services:
   cat /root/enabled_services.txt

3. If services need to be enabled manually:
   ${YELLOW}sudo systemctl enable --now NetworkManager${NC}
   ${YELLOW}sudo systemctl enable --now cups${NC}
   ${YELLOW}sudo systemctl enable --now bluetooth${NC}
   ${YELLOW}sudo systemctl enable --now earlyoom${NC}
   ${YELLOW}sudo systemctl enable --now irqbalance${NC}
   ${YELLOW}sudo systemctl enable --now tuned${NC}

4. To verify services are running:
   ${YELLOW}systemctl status NetworkManager cups bluetooth earlyoom irqbalance tuned${NC}

5. Install DankMaterialShell:
   ${YELLOW}Follow the installation instructions for DankMaterialShell${NC}

${GREEN}Reboot command:${NC} ${YELLOW}reboot${NC}

EOF
