#!/bin/bash
# Arch Linux automated installer with maximum compatibility & performance
# Run from Arch live environment as root. All data on target disk will be lost.

set -e  # exit on error
trap 'echo "Error on line $LINENO. Unmounting..." && umount -R /mnt 2>/dev/null' ERR

# ------------------- CONFIGURATION (edit these) -------------------
DISK="/dev/vda"               # Target disk (will be completely wiped!)
HOSTNAME="ominoussagePC"            # Desired hostname
USERNAME="ominoussage"               # Regular username
PASSWORD="tsuchiya145609"           # TEMPORARY password (change after first boot)
TIMEZONE="Asia/Manila"   # Use "timedatectl list-timezones" to find yours
LOCALE="en_US.UTF-8"          # System locale
# -------------------------------------------------------------------

# Root check
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Internet check
ping -c 1 archlinux.org >/dev/null 2>&1 || { echo "No internet connection."; exit 1; }

# Verify disk exists
if [ ! -b "$DISK" ]; then
    echo "Disk $DISK does not exist."
    exit 1
fi

echo "Installing to $DISK. ALL DATA WILL BE WIPED."
read -rp "Press Enter to continue or Ctrl+C to abort."

# Detect UEFI or BIOS
if [ -d /sys/firmware/efi ]; then
    EFI_MODE=1
    echo "UEFI mode detected."
else
    EFI_MODE=0
    echo "BIOS mode detected (Legacy)."
fi

# Partition disk (GPT)
echo "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
if [ $EFI_MODE -eq 1 ]; then
    # UEFI: 512 MiB EFI partition, rest for root
    parted -s "$DISK" mkpart primary fat32 1MiB 512MiB set 1 esp on
    parted -s "$DISK" mkpart primary ext4 512MiB 100%
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
else
    # BIOS: single root partition (boot flag helps some firmware)
    parted -s "$DISK" mkpart primary ext4 1MiB 100% set 1 boot on
    ROOT_PART="${DISK}1"
fi

# Format partitions
echo "Formatting partitions..."
if [ $EFI_MODE -eq 1 ]; then
    mkfs.fat -F32 "$EFI_PART"
fi
mkfs.ext4 -F "$ROOT_PART"

# Mount root
mount "$ROOT_PART" /mnt

if [ $EFI_MODE -eq 1 ]; then
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
fi

# Install base system + compatibility/performance packages
echo "Installing base system and additional packages..."
pacstrap /mnt \
    base base-devel \
    linux-firmware            # firmware for most hardware
    amd-ucode intel-ucode     # CPU microcode
    mesa vulkan-radeon vulkan-intel vulkan-icd-loader  # GPU drivers & Vulkan
    xf86-video-amdgpu xf86-video-intel xf86-video-nouveau # open-source GPU drivers
    pipewire pipewire-alsa pipewire-pulse wireplumber    # audio
    alsa-firmware sof-firmware                           # audio firmware
    ntfs-3g exfatprogs dosfstools                         # filesystem tools
    bluez bluez-utils                                     # bluetooth
    networkmanager vim sudo git                           # basic tools
    tuned irqbalance earlyoom                             # performance tweaks
    open-vm-tools qemu-guest-agent                        # VM guest agents
    limine                                                # bootloader

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Get root partition UUID for bootloader config
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# Chroot and configure
echo "Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<EOF
set -e

# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
sed -i 's/^#$LOCALE/$LOCALE/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Hostname
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Network
systemctl enable NetworkManager

# Set passwords
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Enable performance services
systemctl enable tuned irqbalance earlyoom
# Enable guest agents (they start automatically if running in respective VM)
systemctl enable vmtoolsd qemu-guest-agent

# Bluetooth (disabled by default; user can start if needed)
systemctl enable bluetooth

# Install liquorix kernel (script adds repo and installs kernel + headers)
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# --- Limine bootloader setup ---
if [ $EFI_MODE -eq 1 ]; then
    # UEFI: copy EFI executable and limine.sys to /boot (EFI partition)
    mkdir -p /boot/EFI/BOOT
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
    cp /usr/share/limine/limine.sys /boot/
else
    # BIOS: install limine to disk MBR and copy limine.sys to /boot
    limine bios-install "$DISK"
    cp /usr/share/limine/limine.sys /boot/
fi

# Create limine configuration file in /boot
cat > /boot/limine.conf <<LIMINE
timeout: 5

# Entry for Arch Linux with Liquorix kernel (microcode loaded first)
:Arch Linux
    comment=Boot with liquorix kernel
    protocol=linux
    kernel_path = boot:///vmlinuz-linux-liquorix
    kernel_cmdline = root=UUID=$ROOT_UUID rw
    initrd_path = boot:///amd-ucode.img boot:///intel-ucode.img boot:///initramfs-linux-liquorix.img
LIMINE

EOF

# Unmount and finish
echo "Installation complete. Unmounting..."
umount -R /mnt
echo "You can now reboot. After reboot, log in and change passwords immediately."
