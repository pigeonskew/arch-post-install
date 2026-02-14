#!/bin/bash
# Arch Linux automated installer with maximum compatibility & performance
# Run from Arch live environment as root. All data on target disk will be lost.

set -e
trap 'echo "Error on line $LINENO. Unmounting..." && umount -R /mnt 2>/dev/null' ERR

# --- Helper functions for interactive prompts ---
prompt_string() {
    local var_name="$1"
    local prompt_text="$2"
    local default="$3"
    local value
    if [ -n "$default" ]; then
        read -rp "$prompt_text [$default]: " value
        value="${value:-$default}"
    else
        read -rp "$prompt_text: " value
    fi
    eval "$var_name=\"$value\""
}

prompt_password() {
    local var_name="$1"
    local prompt_text="$2"
    local password password_confirm
    while true; do
        read -rsp "$prompt_text: " password
        echo
        read -rsp "Confirm password: " password_confirm
        echo
        if [ "$password" = "$password_confirm" ]; then
            break
        else
            echo "Passwords do not match. Try again."
        fi
    done
    eval "$var_name=\"$password\""
}

# --- Root check ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# --- Internet check ---
ping -c 1 archlinux.org >/dev/null 2>&1 || { echo "No internet connection."; exit 1; }

# --- Interactive configuration ---
echo "Welcome to the Arch Linux automated installer."
echo "Please provide the following configuration details."
echo

# List available disks
echo "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
echo

# Prompt for disk
while true; do
    prompt_string DISK "Enter the target disk (e.g., /dev/sda)" ""
    if [ -b "$DISK" ]; then
        break
    else
        echo "Disk $DISK does not exist. Please enter a valid disk."
    fi
done

prompt_string HOSTNAME "Enter hostname" "archbox"
prompt_string USERNAME "Enter username for regular user" "user"
prompt_password PASSWORD "Enter password for user and root (temporary)"

prompt_string TIMEZONE "Enter timezone (e.g., America/New_York)" "America/New_York"
prompt_string LOCALE "Enter locale (e.g., en_US.UTF-8)" "en_US.UTF-8"

echo
echo "Installation will be performed with the following settings:"
echo "  Disk:       $DISK"
echo "  Hostname:   $HOSTNAME"
echo "  Username:   $USERNAME"
echo "  Timezone:   $TIMEZONE"
echo "  Locale:     $LOCALE"
echo "  (Password hidden)"
echo
read -rp "Press Enter to continue or Ctrl+C to abort."

# --- Detect UEFI or BIOS ---
if [ -d /sys/firmware/efi ]; then
    EFI_MODE=1
    echo "UEFI mode detected."
else
    EFI_MODE=0
    echo "BIOS mode detected (Legacy)."
fi

# --- Partition disk (GPT) ---
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

# --- Format partitions ---
echo "Formatting partitions..."
if [ $EFI_MODE -eq 1 ]; then
    mkfs.fat -F32 "$EFI_PART"
fi
mkfs.ext4 -F "$ROOT_PART"

# --- Mount partitions ---
mount "$ROOT_PART" /mnt
if [ $EFI_MODE -eq 1 ]; then
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
fi

# --- Install base system + compatibility/performance packages ---
echo "Installing base system and additional packages..."
pacstrap /mnt \
    base base-devel \
    linux-firmware \
    amd-ucode intel-ucode \
    mesa vulkan-radeon vulkan-intel vulkan-icd-loader \
    xf86-video-amdgpu xf86-video-intel xf86-video-nouveau \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    alsa-firmware sof-firmware \
    ntfs-3g exfatprogs dosfstools \
    bluez bluez-utils \
    networkmanager vim sudo git \
    tuned irqbalance earlyoom \
    open-vm-tools qemu-guest-agent \
    limine

# --- Generate fstab ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- Get root partition UUID ---
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# --- Chroot and configure ---
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

# Enable network manager
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
# Enable bluetooth (disabled by default; user can start if needed)
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

# --- Unmount and finish ---
echo "Installation complete. Unmounting..."
umount -R /mnt
echo "You can now reboot. After reboot, log in and change passwords immediately."
