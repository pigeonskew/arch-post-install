#!/bin/bash
# Arch Linux automated installer (interactive) – safe to share on GitHub
# Run from Arch live environment as root.

set -e
trap 'echo "Error on line $LINENO. Unmounting..." && umount -R /mnt 2>/dev/null' ERR

# --- Fix for piped scripts: redirect input from terminal ---
# This ensures read commands work even when script is piped
exec < /dev/tty

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
echo "Checking internet connection..."
ping -c 1 archlinux.org >/dev/null 2>&1 || { echo "No internet connection."; exit 1; }

# --- Interactive configuration ---
clear
echo "============================================="
echo "   Arch Linux Automated Installer"
echo "============================================="
echo
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

# --- Confirm disk partitioning ---
echo
echo "WARNING: This will DESTROY ALL DATA on $DISK"
read -rp "Type 'YES' to continue: " confirm
if [ "$confirm" != "YES" ]; then
    echo "Installation cancelled."
    exit 1
fi

# --- Partition disk (GPT) ---
echo "Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
if [ $EFI_MODE -eq 1 ]; then
    # UEFI: 512 MiB EFI partition, rest for root
    parted -s "$DISK" mkpart primary fat32 1MiB 512MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 512MiB 100%
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
else
    # BIOS: single root partition
    parted -s "$DISK" mkpart primary ext4 1MiB 100%
    parted -s "$DISK" set 1 boot on
    ROOT_PART="${DISK}1"
fi

# Wait for partition table to update
sleep 2
partprobe "$DISK" 2>/dev/null || true
sleep 1

# --- Format partitions ---
echo "Formatting partitions..."
if [ $EFI_MODE -eq 1 ]; then
    mkfs.fat -F32 "$EFI_PART"
fi
mkfs.ext4 -F "$ROOT_PART"

# --- Mount partitions ---
echo "Mounting partitions..."
mount "$ROOT_PART" /mnt
if [ $EFI_MODE -eq 1 ]; then
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
fi

# --- Install base system ---
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
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- Get root partition UUID ---
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

# --- Chroot and configure ---
echo "Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<'CHROOT_EOF'
set -e

# Timezone
ln -sf /usr/share/zoneinfo/'"$TIMEZONE"' /etc/localtime
hwclock --systohc

# Locale
sed -i 's/^#'"$LOCALE"'/'"$LOCALE"'/' /etc/locale.gen
locale-gen
echo "LANG='"$LOCALE"'" > /etc/locale.conf

# Hostname
echo "'"$HOSTNAME"'" > /etc/hostname
cat > /etc/hosts <<HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   '"$HOSTNAME"'.localdomain '"$HOSTNAME"'
HOSTS_EOF

# Enable network manager
systemctl enable NetworkManager

# Set passwords
echo "root:'"$PASSWORD"'" | chpasswd
useradd -m -G wheel '"$USERNAME"'
echo "'"$USERNAME"':'"$PASSWORD"'" | chpasswd

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable tuned irqbalance earlyoom
systemctl enable vmtoolsd qemu-guest-agent
systemctl enable bluetooth

# Install liquorix kernel
echo "Installing Liquorix kernel..."
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# --- Limine bootloader setup ---
if [ '"$EFI_MODE"' -eq 1 ]; then
    # UEFI
    mkdir -p /boot/EFI/BOOT
    cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
    cp /usr/share/limine/limine.sys /boot/
else
    # BIOS
    limine bios-install '"$DISK"'
    cp /usr/share/limine/limine.sys /boot/
fi

# Create limine configuration
cat > /boot/limine.conf <<LIMINE_EOF
timeout: 5

:Arch Linux
    comment=Boot with liquorix kernel
    protocol=linux
    kernel_path = boot:///vmlinuz-linux-liquorix
    kernel_cmdline = root=UUID='"$ROOT_UUID"' rw
    initrd_path = boot:///amd-ucode.img boot:///intel-ucode.img boot:///initramfs-linux-liquorix.img
LIMINE_EOF

CHROOT_EOF

# --- Unmount and finish ---
echo "Installation complete. Unmounting..."
umount -R /mnt

echo
echo "============================================="
echo "   Installation Complete!"
echo "============================================="
echo "You can now reboot with: reboot"
echo
echo "After reboot:"
echo "  - Log in as $USERNAME (password you set)"
echo "  - Change your password with: passwd"
echo "  - Change root password with: sudo passwd"
echo "============================================="
