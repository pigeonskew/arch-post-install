#!/bin/bash

# Arch Linux Post-Install Setup Script
# Installs essential packages for hardware/software compatibility and performance

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Function for colored output
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[x]${NC} $1"
}

# Update system first
print_status "Updating system packages..."
pacman -Syu --noconfirm

# Install essential hardware support packages
print_status "Installing hardware support packages..."

# CPU microcode (both Intel and AMD)
pacman -S --noconfirm amd-ucode intel-ucode

# Firmware packages
pacman -S --noconfirm linux-firmware sof-firmware

# Basic drivers and utilities
pacman -S --noconfirm \
    mesa \
    vulkan-radeon vulkan-intel vulkan-icd-loader \
    libva-mesa-driver mesa-vdpau intel-media-driver \
    xf86-video-amdgpu xf86-video-ati xf86-video-intel xf86-video-nouveau \
    xf86-input-libinput \
    alsa-utils pulseaudio pulseaudio-alsa pavucontrol \
    bluez bluez-utils \
    networkmanager network-manager-applet wpa_supplicant \
    git curl wget base-devel

# Performance and compatibility utilities
print_status "Installing performance and system utilities..."

pacman -S --noconfirm \
    cpupower thermald lm_sensors \
    dmidecode pciutils usbutils \
    f2fs-tools btrfs-progs xfsprogs ntfs-3g exfatprogs \
    smartmontools hdparm \
    acpi acpid \
    cronie \
    neofetch htop btop \
    unzip unrar p7zip \
    gvfs gvfs-mtp gvfs-smb \
    ntfs-3g exfat-utils \
    man-db man-pages \
    bash-completion \
    nano vim \
    openssh \
    cups cups-pdf \
    sane sane-airscan \
    tlp ethtool

# Install Liquorix kernel
print_status "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Install systemd services for performance
print_status "Configuring system services..."

# Enable essential services
systemctl enable --now NetworkManager
systemctl enable --now bluetooth
systemctl enable --now cpupower
systemctl enable --now thermald
systemctl enable --now cronie
systemctl enable --now acpid
systemctl enable --now tlp
systemctl enable --now cups
systemctl enable --now sshd

# Configure cpupower for performance
cpupower frequency-set -g performance

# Create basic directories for user compatibility
print_status "Creating user directories..."
mkdir -p /etc/skel/{Desktop,Documents,Downloads,Music,Pictures,Public,Templates,Videos}

# Install development tools for compatibility
print_status "Installing development tools for software compatibility..."
pacman -S --noconfirm \
    python python-pip \
    nodejs npm \
    jre-openjdk jdk-openjdk \
    go \
    rust \
    docker docker-compose \
    flatpak snapd

# Enable docker and snapd services
systemctl enable --now docker
systemctl enable --now snapd.socket

# Install additional codecs
print_status "Installing multimedia codecs..."
pacman -S --noconfirm \
    gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
    gst-libav \
    ffmpeg ffmpegthumbs \
    flac faac faad2 \
    jasper libdvdcss libdvdread libdvdnav

# Install fonts for better compatibility
print_status "Installing font packages..."
pacman -S --noconfirm \
    noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra \
    ttf-dejavu ttf-liberation ttf-opensans \
    freetype2

# Install printing support
pacman -S --noconfirm system-config-printer

# Configure sudo for user convenience (uncomment to enable)
# print_status "Configuring sudo..."
# echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel

# Clean up
print_status "Cleaning up..."
pacman -Sc --noconfirm

# Update initramfs for new kernel
print_status "Updating initramfs..."
mkinitcpio -P

print_status "Installation complete!"
print_warning "Please note:"
echo "1. Reboot to use the Liquorix kernel"
echo "2. Install your preferred desktop environment/window manager"
echo "3. Install DankMaterialShell or your preferred shell"
echo "4. Configure user-specific settings"
echo ""
echo "For NVIDIA users, consider installing:"
echo "  nvidia nvidia-utils nvidia-settings"
echo ""
echo "For VirtualBox guests, install:"
echo "  virtualbox-guest-utils"

# Prompt for reboot
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi
