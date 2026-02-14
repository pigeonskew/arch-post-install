#!/bin/bash

# Arch Linux Automated Installation Script
# With Limine bootloader and Liquorix kernel
# For maximum software/hardware compatibility and performance

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root"
    exit 1
fi

# Welcome message
clear
print_status "Arch Linux Automated Installation Script"
print_status "This script will install Arch Linux with Limine bootloader and Liquorix kernel"
echo ""

# Get user input for configuration
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -sp "Enter password for $USERNAME: " USER_PASSWORD
echo ""
read -sp "Enter root password: " ROOT_PASSWORD
echo ""
read -p "Enter timezone (e.g., America/New_York): " TIMEZONE
read -p "Enter keyboard layout (e.g., us): " KEYMAP

# Disk selection
print_status "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Enter disk to install to (e.g., /dev/sda): " DISK

# Confirm installation
print_warning "This will DESTROY ALL DATA on $DISK"
read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_status "Installation cancelled"
    exit 0
fi

# Partition the disk
print_status "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 100%

# Format partitions
print_status "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"
mkfs.ext4 -F "${DISK}2"

# Mount partitions
print_status "Mounting partitions..."
mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base system
print_status "Installing base system..."
pacstrap /mnt base base-devel linux-firmware nano sudo networkmanager

# Generate fstab
print_status "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and configure system
print_status "Configuring system..."

cat << EOF | arch-chroot /mnt
# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set keyboard layout
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set hosts file
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable NetworkManager
systemctl enable NetworkManager

# Install Limine bootloader
print_status "Installing Limine bootloader..."
pacman -S --noconfirm limine

# Install Limine to disk
limine bios-install $DISK

# Configure Limine
mkdir -p /boot/limine
cat > /boot/limine/limine.conf << LIMINE
timeout: 5

/Directory: /boot

/Arch Linux
    protocol: linux
    kernel_path: boot:/vmlinuz-linux-liquorix
    kernel_cmdline: root=UUID=$(blkid -s UUID -o value ${DISK}2) rw
    module_path: boot:/initramfs-linux-liquorix.img
LIMINE

# Install Liquorix kernel
print_status "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Install essential packages for maximum compatibility
print_status "Installing essential packages..."
pacman -S --noconfirm \
    # Core utilities
    htop \
    neofetch \
    git \
    wget \
    curl \
    unzip \
    zip \
    p7zip \
    tar \
    gzip \
    bzip2 \
    xz \
    zstd \
    \
    # Development tools
    gcc \
    make \
    cmake \
    autoconf \
    automake \
    pkg-config \
    \
    # Hardware compatibility
    mesa \
    vulkan-intel \
    vulkan-radeon \
    vulkan-amdgpu \
    nvidia-dkms \
    nvidia-utils \
    nvidia-settings \
    libva \
    libva-intel-driver \
    libva-mesa-driver \
    intel-media-driver \
    \
    # Audio
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    alsa-utils \
    \
    # Bluetooth
    bluez \
    bluez-utils \
    \
    # Printing
    cups \
    hplip \
    \
    # Network
    networkmanager-openvpn \
    networkmanager-pptp \
    networkmanager-vpnc \
    iwd \
    \
    # File systems
    ntfs-3g \
    exfat-utils \
    dosfstools \
    btrfs-progs \
    xfsprogs \
    f2fs-tools \
    \
    # Codecs and multimedia
    ffmpeg \
    gst-plugins-base \
    gst-plugins-good \
    gst-plugins-bad \
    gst-plugins-ugly \
    gst-libav \
    \
    # Fonts
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation \
    ttf-droid \
    \
    # Performance tools
    irqbalance \
    cpupower \
    tuned \
    earlyoom \
    preload \
    \
    # System utilities
    polkit \
    udisks2 \
    upower \
    acpi \
    acpid \
    tlp \
    powertop \
    thermald \
    \
    # Security
    firewalld \
    openssh \
    \
    # X11 and Wayland (minimal)
    xorg-xrandr \
    xorg-xrdb \
    xorg-xsetroot \
    xorg-xset \
    xdg-user-dirs \
    xdg-utils \
    \
    # Firmware
    sof-firmware \
    alsa-firmware \
    alsa-ucm-conf

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups
systemctl enable firewalld
systemctl enable earlyoom
systemctl enable preload
systemctl enable irqbalance
systemctl enable tuned
systemctl enable tlp
systemctl enable thermald
systemctl enable acpid
systemctl enable upower
systemctl enable udisks2

# Performance tweaks
print_status "Applying performance tweaks..."

# Enable TRIM for SSD (if applicable)
systemctl enable fstrim.timer

# Configure sysctl for performance
cat >> /etc/sysctl.d/99-performance.conf << SYSCTL
# Increase system file limits
fs.file-max = 2097152

# Increase network performance
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.core.optmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Enable TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Reduce swap usage
vm.swappiness = 10
vm.vfs_cache_pressure = 50

# Improve disk I/O performance
vm.dirty_ratio = 30
vm.dirty_background_ratio = 5
SYSCTL

# Configure CPU governor for performance
cat > /etc/tmpfiles.d/cpupower.conf << CPU
w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor - - - - performance
CPU

# Create user directories
xdg-user-dirs-update

print_status "Installation complete!"
print_status "System configured with Limine bootloader and Liquorix kernel"
print_status "You can now reboot into your new Arch Linux system"
print_status "After reboot, you can install DankMaterialShell or any other custom shell"
EOF

# Unmount partitions
print_status "Unmounting partitions..."
umount -R /mnt

print_status "Installation completed successfully!"
print_warning "Please remove the installation media and reboot"
