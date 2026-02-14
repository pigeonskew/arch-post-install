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

# Chroot and configure system
print_status "Configuring system..."
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Configure locale
echo "$LOCALE1 UTF-8" >> /etc/locale.gen
if [ -n "$LOCALE2" ]; then
    echo "$LOCALE2 UTF-8" >> /etc/locale.gen
fi
locale-gen

echo "LANG=$LOCALE1" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set hosts file
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Install and configure bootloader (GRUB)
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Install essential packages for compatibility and performance
pacman -S --noconfirm \
    # System utilities
    htop \
    neofetch \
    man-db \
    man-pages \
    texinfo \
    networkmanager \
    openssh \
    reflector \
    git \
    curl \
    wget \
    unzip \
    zip \
    p7zip \
    ntfs-3g \
    dosfstools \
    
    # Hardware compatibility
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
    nvidia-utils \
    
    # Audio
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    
    # Printing support
    cups \
    cups-pdf \
    
    # Bluetooth
    bluez \
    bluez-utils \
    
    # Performance tools
    earlyoom \
    irqbalance \
    tuned \
    cpupower \
    
    # File systems support
    btrfs-progs \
    exfatprogs \
    f2fs-tools \
    xfsprogs \
    
    # Development tools (but minimal)
    gcc \
    make \
    pkg-config
    
# Enable essential services
systemctl enable NetworkManager
systemctl enable cups
systemctl enable bluetooth
systemctl enable earlyoom
systemctl enable irqbalance
systemctl enable tuned

# Optimize pacman configuration
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

# Install Liquorix kernel using the provided curl command
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Update GRUB after kernel installation
grub-mkconfig -o /boot/grub/grub.cfg

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

EOF

# Unmount partitions
print_status "Unmounting partitions..."
umount -R /mnt

print_status "Installation complete!"
print_status "You can now reboot into your new Arch Linux system"
print_status "After reboot, run: systemctl start tuned && sudo tuned-adm profile latency-performance"

print_warning "Don't forget to install DankMaterialShell manually after first boot!"
print_warning "Reboot command: reboot"
