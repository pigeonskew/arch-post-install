#!/bin/bash

# Arch Linux Post-Installation Compatibility Script
# Run as root or with sudo after barebones Arch installation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Update system first
log "Updating system..."
pacman -Syu --noconfirm

# Enable multilib repository for 32-bit compatibility
log "Enabling multilib repository..."
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    cat >> /etc/pacman.conf << 'EOF'

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    pacman -Sy
fi

# Install Liquorix kernel (performance-optimized)
log "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Hardware compatibility - CPU microcode
log "Installing CPU microcode..."
if grep -q "Intel" /proc/cpuinfo; then
    pacman -S --noconfirm intel-ucode
elif grep -q "AMD" /proc/cpuinfo; then
    pacman -S --noconfirm amd-ucode
fi

# Essential firmware
log "Installing firmware..."
pacman -S --noconfirm linux-firmware

# Hardware detection and drivers
log "Installing hardware detection tools..."
pacman -S --noconfirm pciutils usbutils dmidecode lshw

# Graphics drivers (detect and install appropriate ones)
log "Detecting and installing graphics drivers..."

# Check for NVIDIA
if lspci | grep -i nvidia > /dev/null; then
    warn "NVIDIA GPU detected - installing proprietary drivers"
    pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
    # For 32-bit compatibility
    pacman -S --noconfirm lib32-nvidia-utils
fi

# Check for AMD/ATI
if lspci | grep -i "amd\|ati" > /dev/null; then
    log "AMD GPU detected - installing open-source drivers"
    pacman -S --noconfirm xf86-video-amdgpu vulkan-radeon libva-mesa-driver mesa-vdpau
    pacman -S --noconfirm lib32-mesa lib32-vulkan-radeon
fi

# Check for Intel
if lspci | grep -i "intel.*graphics" > /dev/null; then
    log "Intel GPU detected"
    pacman -S --noconfirm xf86-video-intel vulkan-intel intel-media-driver
    pacman -S --noconfirm lib32-mesa lib32-vulkan-intel
fi

# Base utilities
log "Installing base utilities..."
pacman -S --noconfirm \
    base-devel \
    git \
    wget \
    curl \
    man-db \
    man-pages \
    texinfo \
    sudo \
    which \
    file \
    findutils \
    grep \
    sed \
    awk \
    tar \
    gzip \
    bzip2 \
    xz \
    zip \
    unzip \
    p7zip \
    unrar

# Networking essentials
log "Installing networking tools..."
pacman -S --noconfirm \
    networkmanager \
    network-manager-applet \
    dhcpcd \
    iwd \
    openssh \
    rsync \
    traceroute \
    bind \
    whois \
    nmap \
    net-tools \
    inetutils \
    ethtool \
    wireless_tools \
    wpa_supplicant

# Audio system (PipeWire - modern standard)
log "Installing audio system (PipeWire)..."
pacman -S --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    pavucontrol \
    alsa-utils \
    alsa-plugins

# Bluetooth
log "Installing Bluetooth support..."
pacman -S --noconfirm \
    bluez \
    bluez-utils \
    blueman

# Printing support
log "Installing printing support..."
pacman -S --noconfirm \
    cups \
    cups-pdf \
    ghostscript \
    gsfonts \
    foomatic-db-engine \
    foomatic-db-gutenprint-ppds \
    gutenprint \
    system-config-printer

# File systems support
log "Installing filesystem support..."
pacman -S --noconfirm \
    dosfstools \
    ntfs-3g \
    exfatprogs \
    btrfs-progs \
    xfsprogs \
    reiserfsprogs \
    jfsutils \
    nfs-utils \
    samba \
    cifs-utils \
    sshfs \
    fuse3

# Archive formats
log "Installing additional archive support..."
pacman -S --noconfirm \
    unarchiver \
    lrzip \
    lzop \
    zstd

# Hardware monitoring and sensors
log "Installing hardware monitoring..."
pacman -S --noconfirm \
    lm_sensors \
    dmidecode \
    smartmontools \
    hdparm \
    nvme-cli

# Power management
log "Installing power management..."
pacman -S --noconfirm \
    tlp \
    tlp-rdw \
    powertop

# Fonts (essential only)
log "Installing essential fonts..."
pacman -S --noconfirm \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    noto-fonts-extra \
    ttf-liberation \
    ttf-dejavu \
    ttf-roboto \
    ttf-font-awesome

# Input method (for international users)
log "Installing input method support..."
pacman -S --noconfirm \
    fcitx5 \
    fcitx5-configtool \
    fcitx5-gtk \
    fcitx5-qt \
    fcitx5-unikey \
    fcitx5-chinese-addons

# Essential libraries (32-bit compatibility for gaming/proprietary software)
log "Installing 32-bit libraries..."
pacman -S --noconfirm \
    lib32-gcc-libs \
    lib32-glibc \
    lib32-zlib \
    lib32-bzip2 \
    lib32-libstdc++5 \
    lib32-openssl \
    lib32-libx11 \
    lib32-libxcb \
    lib32-libxext \
    lib32-libxinerama \
    lib32-libxrandr \
    lib32-libxss \
    lib32-libxtst \
    lib32-libdrm \
    lib32-libglvnd \
    lib32-libpulse \
    lib32-alsa-lib \
    lib32-alsa-plugins \
    lib32-libusb \
    lib32-nspr \
    lib32-nss \
    lib32-gtk2 \
    lib32-gtk3 \
    lib32-pango \
    lib32-cairo \
    lib32-freetype2 \
    lib32-fontconfig \
    lib32-libpng \
    lib32-libjpeg-turbo \
    lib32-libtiff \
    lib32-libxml2 \
    lib32-expat \
    lib32-dbus \
    lib32-systemd \
    lib32-curl \
    lib32-libffi \
    lib32-gettext \
    lib32-harfbuzz \
    lib32-libcups \
    lib32-libgcrypt \
    lib32-libgpg-error \
    lib32-lz4 \
    lib32-xz \
    lib32-zstd \
    lib32-vulkan-icd-loader

# Multimedia codecs
log "Installing multimedia codecs..."
pacman -S --noconfirm \
    ffmpeg \
    ffmpegthumbnailer \
    gst-plugins-base \
    gst-plugins-good \
    gst-plugins-bad \
    gst-plugins-ugly \
    gst-libav \
    gstreamer-vaapi \
    libva-utils \
    vdpauinfo \
    mesa-demos \
    vulkan-tools

# Additional hardware support
log "Installing additional hardware support..."

# Touchpad support
pacman -S --noconfirm xf86-input-libinput

# Tablet/Wacom support
pacman -S --noconfirm xf86-input-wacom libwacom

# Webcam support
pacman -S --noconfirm v4l-utils

# Scanner support
pacman -S --noconfirm sane sane-airscan

# Enable essential services
log "Enabling system services..."
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups.socket
systemctl enable tlp
systemctl enable fstrim.timer
systemctl enable reflector.timer 2>/dev/null || true

# Configure mkinitcpio for Liquorix and microcode
log "Configuring initramfs..."
if grep -q "intel-ucode" /proc/cpuinfo 2>/dev/null || [[ -f /boot/intel-ucode.img ]]; then
    sed -i 's/^HOOKS=(base udev/HOOKS=(base udev microcode/' /etc/mkinitcpio.conf
fi
mkinitcpio -P

# Install bootloader entries for Liquorix
log "Updating bootloader..."
if [[ -d /boot/loader/entries ]]; then
    # systemd-boot
    log "Detected systemd-boot, creating entry for Liquorix..."
    # Entry will be created automatically by install script, but ensure it's there
    bootctl update
elif [[ -f /boot/grub/grub.cfg ]]; then
    # GRUB
    log "Detected GRUB, regenerating config..."
    grub-mkconfig -o /boot/grub/grub.cfg
fi

# AUR helper setup (yay - for packages not in official repos)
log "Installing yay AUR helper..."
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Install additional firmware from AUR if needed
log "Installing additional firmware from AUR..."
yay -S --noconfirm \
    upd72020x-fw \
    aic94xx-firmware \
    wd719x-firmware \
    linux-firmware-whence \
    mkinitcpio-firmware || true

# Cleanup
log "Cleaning up..."
rm -rf /tmp/yay
pacman -Sc --noconfirm

# Final message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "System is now configured for maximum compatibility."
echo ""
echo "Next steps:"
echo "1. Reboot to load Liquorix kernel"
echo "2. Install your custom shell (DankMaterialShell)"
echo "3. Configure your desktop environment"
echo ""
echo "Post-reboot checks:"
echo "- Run 'sensors-detect' as root to configure hardware sensors"
echo "- Run 'mkinitcpio -P' if you modify kernel modules"
echo ""
echo -e "${YELLOW}Note: Some proprietary drivers may require additional configuration${NC}"
