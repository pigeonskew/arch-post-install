#!/usr/bin/env bash
#
# Arch Linux automated installer with Liquorix kernel, extra repos, and performance tweaks
# Run this script from an Arch Linux live environment as root.
#

set -e  # exit on error
set -u  # treat unset variables as error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG="/root/arch_install.log"
exec > >(tee -a "$LOG") 2>&1

# Helper functions
die() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

confirm() {
    read -r -p "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Preliminary checks
[[ $EUID -eq 0 ]] || die "This script must be run as root."
[[ -d /sys/firmware/efi ]] || die "Only UEFI systems are supported by this script."
ping -c 1 archlinux.org &>/dev/null || die "No internet connection."

# Display header
info "========================================="
info "  Arch Linux Automated Installer"
info "========================================="
warn "This script will DESTROY ALL DATA on the selected disk."
confirm "Do you want to continue?" || exit 0

# Select target disk
lsblk -d -o NAME,SIZE,MODEL
echo ""
read -r -p "Enter the target disk (e.g., /dev/sda): " TARGET_DISK
[[ -b "$TARGET_DISK" ]] || die "Invalid disk."

# Ask for automatic partitioning or manual
warn "Choose partitioning method:"
echo "1) Automatic (erase entire disk, create EFI and root partitions)"
echo "2) Manual (I will partition myself and continue)"
read -r -p "Choice [1/2]: " PART_CHOICE

case "$PART_CHOICE" in
    1)
        info "Automatic partitioning selected."
        # Wipe disk
        wipefs -a "$TARGET_DISK"
        # Partition: 512M EFI, rest root
        parted "$TARGET_DISK" -- mklabel gpt
        parted "$TARGET_DISK" -- mkpart ESP fat32 1MiB 512MiB
        parted "$TARGET_DISK" -- set 1 esp on
        parted "$TARGET_DISK" -- mkpart primary 512MiB 100%
        # Wait for kernel to see new partitions
        sleep 2
        partprobe "$TARGET_DISK"
        # Identify partition names (handle NVMe vs SATA)
        if [[ "$TARGET_DISK" == *"nvme"* ]]; then
            EFI_PART="${TARGET_DISK}p1"
            ROOT_PART="${TARGET_DISK}p2"
        else
            EFI_PART="${TARGET_DISK}1"
            ROOT_PART="${TARGET_DISK}2"
        fi
        # Format partitions
        mkfs.fat -F32 "$EFI_PART"
        mkfs.ext4 -F "$ROOT_PART"
        ;;
    2)
        info "Manual partitioning. Please partition $TARGET_DISK now."
        info "Create an EFI partition (type EFI System) and a root partition."
        read -r -p "Press Enter when ready..."
        # Ask for partition paths
        lsblk "$TARGET_DISK"
        read -r -p "Enter EFI partition (e.g., ${TARGET_DISK}1): " EFI_PART
        read -r -p "Enter root partition (e.g., ${TARGET_DISK}2): " ROOT_PART
        [[ -b "$EFI_PART" && -b "$ROOT_PART" ]] || die "Invalid partitions."
        # Optionally ask if they want to format (default yes)
        if confirm "Format EFI partition as FAT32?"; then
            mkfs.fat -F32 "$EFI_PART"
        fi
        if confirm "Format root partition as ext4?"; then
            mkfs.ext4 -F "$ROOT_PART"
        fi
        ;;
    *)
        die "Invalid choice."
        ;;
esac

# Mount partitions
info "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# Install base system
info "Installing base system (this may take a while)..."
pacstrap /mnt base base-devel linux-firmware vim sudo curl git

# Generate fstab
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and configure
info "Entering chroot to configure system..."
cat << 'EOF' | arch-chroot /mnt /bin/bash
set -e
set -u

# Set timezone
echo "Setting timezone..."
TIMEZONE="$(curl -s http://ip-api.com/line?fields=timezone)"
if [[ -z "$TIMEZONE" || ! -f "/usr/share/zoneinfo/$TIMEZONE" ]]; then
    TIMEZONE="UTC"
fi
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# Locale (only two locales)
echo "Configuring locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "Choose second locale (leave empty to skip):"
read -r SECOND_LOCALE
if [[ -n "$SECOND_LOCALE" ]]; then
    echo "$SECOND_LOCALE UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
read -r -p "Enter hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root password
echo "Set root password:"
passwd

# Create user
read -r -p "Enter username: " USERNAME
useradd -m -G wheel,audio,video,storage -s /bin/bash "$USERNAME"
echo "Set password for $USERNAME:"
passwd "$USERNAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# Install and configure bootloader (GRUB)
info "Installing GRUB..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable essential services
systemctl enable NetworkManager

# Add extra repositories
info "Adding extra repositories..."

# Multilib (uncomment)
sed -i 's/^#\[multilib\]/\[multilib\]/' /etc/pacman.conf
sed -i '/^\[multilib\]/,/^Include/ s/^#Include/Include/' /etc/pacman.conf

# Chaotic-AUR
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf

# Refresh package databases
pacman -Sy --noconfirm

# Install Liquorix kernel using the provided curl command
info "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Install essential packages for compatibility and performance
info "Installing packages for maximum compatibility and performance..."
pacman -S --noconfirm \
    # Graphics and display
    mesa lib32-mesa vulkan-icd-loader \
    vulkan-radeon lib32-vulkan-radeon \
    vulkan-intel lib32-vulkan-intel \
    nvidia-dkms nvidia-utils lib32-nvidia-utils \
    xf86-video-amdgpu xf86-video-intel xf86-video-nouveau \
    # Audio
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    # Codecs and multimedia
    gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly \
    gst-libav ffmpeg \
    # Networking
    networkmanager iwd openssh \
    # Bluetooth
    bluez bluez-utils \
    # Printing (optional)
    cups \
    # Firmware and microcode
    amd-ucode intel-ucode \
    sof-firmware \
    # Performance tools
    tuned power-profiles-daemon irqbalance thermald \
    # Filesystem tools
    btrfs-progs ntfs-3g exfat-utils \
    # System utilities (useful but not strictly required)
    htop btop neofetch fastfetch \
    # Development tools (for later AUR builds)
    git base-devel

# Enable services
systemctl enable NetworkManager bluetooth cups tuned power-profiles-daemon irqbalance thermald

# Optional: auto-cpufreq (AUR package, can be installed later by user)
# We'll skip it here to keep it simple, but user can install via chaotic-aur later.

# Rebuild initramfs for Liquorix kernel (should be automatic)
mkinitcpio -P

# Set default kernel to liquorix in GRUB (if multiple kernels)
# GRUB already picks the latest installed kernel, but we can ensure by re-running grub-mkconfig
grub-mkconfig -o /boot/grub/grub.cfg

# Done
info "Base system configuration complete."
EOF

# Unmount and finish
info "Unmounting partitions..."
umount -R /mnt

info "Installation finished! You can now reboot."
if confirm "Reboot now?"; then
    reboot
else
    echo "Exiting. You may reboot later with 'reboot'."
fi
