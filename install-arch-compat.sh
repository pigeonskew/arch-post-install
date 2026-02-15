#!/bin/bash

# Arch Linux Automated Installation Script
# Run this script as root from the Arch ISO

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Welcome message
clear
print_status "Welcome to Arch Linux Automated Installer"
print_status "This script will guide you through installing Arch Linux"
echo ""

# User input for system configuration
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter password for $USERNAME: " USER_PASS
echo ""
read -s -p "Enter password for root: " ROOT_PASS
echo ""
read -p "Enter timezone (e.g., America/New_York): " TIMEZONE

# Select disk
print_status "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Enter disk to install to (e.g., /dev/sda): " DISK

# Confirm disk selection
print_warning "WARNING: This will erase ALL data on $DISK"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    print_error "Installation cancelled"
    exit 1
fi

# Select filesystem
echo ""
echo "Select filesystem:"
echo "1) ext4 (standard)"
echo "2) btrfs (with compression and snapshots)"
echo "3) xfs (high performance)"
read -p "Choice [1-3]: " FS_CHOICE

case $FS_CHOICE in
    1) FILESYSTEM="ext4" ;;
    2) FILESYSTEM="btrfs" ;;
    3) FILESYSTEM="xfs" ;;
    *) FILESYSTEM="ext4" ;;
esac

# Partition the disk
print_status "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary $FILESYSTEM 513MiB 100%

# Format partitions
print_status "Formatting partitions..."
mkfs.fat -F32 "${DISK}1"

if [ "$FILESYSTEM" = "btrfs" ]; then
    mkfs.btrfs -f "${DISK}2"
    mount "${DISK}2" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@cache
    btrfs subvolume create /mnt/@log
    umount /mnt
    
    mount -o compress=zstd,subvol=@ "${DISK}2" /mnt
    mkdir -p /mnt/{home,var/cache,var/log}
    mount -o compress=zstd,subvol=@home "${DISK}2" /mnt/home
    mount -o compress=zstd,subvol=@cache "${DISK}2" /mnt/var/cache
    mount -o compress=zstd,subvol=@log "${DISK}2" /mnt/var/log
else
    mkfs.$FILESYSTEM -f "${DISK}2"
    mount "${DISK}2" /mnt
fi

# Create and mount EFI partition
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot

# Install base system
print_status "Installing base system..."
pacstrap /mnt base base-devel linux-firmware

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
echo "en_US ISO-8859-1" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set root password
echo "root:$ROOT_PASS" | chpasswd

# Create user
useradd -m -G wheel,audio,video,storage,power,rfkill -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd

# Configure sudo
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Install bootloader
bootctl install

# Create bootloader entry
cat > /boot/loader/entries/arch.conf << EOF2
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}2) rw
EOF2

# Set default boot entry
echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf

# Install Liquorix kernel
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Install essential packages
pacman -S --noconfirm \
    amd-ucode intel-ucode \
    networkmanager network-manager-applet \
    alsa-utils pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    bluez bluez-utils \
    vulkan-radeon vulkan-intel nvidia-dkms nvidia-utils \
    mesa lib32-mesa \
    xf86-video-amdgpu xf86-video-intel xf86-video-nouveau \
    xf86-input-libinput \
    thermald tlp cpupower \
    earlyoom \
    preload \
    irqbalance \
    ananicy-cpp \
    ufw \
    git curl wget \
    htop btop \
    neovim vim \
    zsh fish \
    firefox \
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
    ttf-dejavu ttf-liberation \
    openssh \
    dosfstools exfatprogs ntfs-3g f2fs-tools \
    zip unzip unrar p7zip \
    reflector \
    pacman-contrib \
    cronie \
    logrotate \
    acpi acpid \
    dmidecode \
    lm_sensors \
    sysfsutils \
    tuned \
    schedtool \
    linux-zen-headers \
    dkms

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable thermald
systemctl enable tlp
systemctl enable earlyoom
systemctl enable preload
systemctl enable irqbalance
systemctl enable ananicy-cpp
systemctl enable ufw
systemctl enable cronie
systemctl enable acpid
systemctl enable tuned
systemctl enable reflector.timer
systemctl enable paccache.timer

# Configure UFW
ufw default deny incoming
ufw default allow outgoing
ufw enable

# Configure tuned
tuned-adm profile latency-performance

# Add additional repositories
cat >> /etc/pacman.conf << EOF3

[multilib]
Include = /etc/pacman.d/mirrorlist

[chaotic-aur]
SigLevel = Never
Server = https://repo.chaotic-aur.org/\$repo/\$arch

[archlinuxcn]
Server = https://repo.archlinuxcn.org/\$arch
EOF3

# Install Chaotic-AUR keyring
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# Install archlinuxcn keyring
pacman -S --noconfirm archlinuxcn-keyring

# Update system
pacman -Syu --noconfirm

# Install AUR helper (yay)
cd /tmp
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
cd /

# Install additional performance packages from AUR
sudo -u $USERNAME yay -S --noconfirm \
    auto-cpufreq \
    systemd-boot-manager \
    gamemode \
    lib32-gamemode \
    mangohud \
    lib32-mangohud \
    vkbasalt \
    goverlay \
    corectrl

# Enable auto-cpufreq
systemctl enable auto-cpufreq

# Configure corectrl for user
cat > /etc/polkit-1/rules.d/90-corectrl.rules << EOF4
polkit.addRule(function(action, subject) {
    if (action.id == "org.corectrl.helper" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF4

# Create swap file if not using btrfs
if [ "$FILESYSTEM" != "btrfs" ]; then
    print_status "Creating swap file..."
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi

# Configure sysctl for performance
cat >> /etc/sysctl.d/99-performance.conf << EOF5
# Increase system limits
vm.max_map_count=2147483642
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5

# Network performance
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 134217728
net.ipv4.tcp_wmem=4096 65536 134217728
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# Kernel performance
kernel.numa_balancing=0
kernel.sched_autogroup_enabled=0
EOF5

# Configure GRUB if using it instead of systemd-boot
# (Optional, commented out by default)
# echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash mitigations=off nowatchdog\" >> /etc/default/grub"

EOF

# Unmount and finish
print_status "Unmounting partitions..."
umount -R /mnt

print_status "Installation complete!"
print_status "You can now reboot into your new Arch Linux system"
print_status "After reboot, you can install DankMaterialShell manually"

echo ""
print_warning "Important notes:"
echo "  - Root password: [as set during installation]"
echo "  - User password: [as set during installation]"
echo "  - Hostname: $HOSTNAME"
echo "  - Filesystem: $FILESYSTEM"
echo ""
print_status "Additional repositories added:"
echo "  - multilib"
echo "  - chaotic-aur"
echo "  - archlinuxcn"
echo ""
print_status "Performance tweaks applied:"
echo "  - Liquorix kernel installed"
echo "  - System services optimized (earlyoom, preload, irqbalance, etc.)"
echo "  - Sysctl performance parameters configured"
echo "  - tuned with latency-performance profile"
echo "  - auto-cpufreq for CPU scaling"
echo "  - Gaming optimizations (gamemode, mangohud, etc.)"
echo ""
print_warning "After first boot, run: sudo auto-cpufreq --install"
