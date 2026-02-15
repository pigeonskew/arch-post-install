#!/bin/bash

# ---------------------------------------------------------
# SAFETY CHECKS
# ---------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

error_exit() {
    echo ":: Error: $1"
    exit 1
}

# ---------------------------------------------------------
# 1. USER INPUT
# ---------------------------------------------------------
clear
echo "=========================================="
echo "   ARCH LINUX AUTOMATED INSTALL SCRIPT   "
echo "=========================================="
echo "WARNING: This script will WIPE the selected disk."
echo ""

# Keyboard Layout
read -p ":: Enter keyboard layout (e.g., us, de, es) [default: us]: " KEYMAP
KEYMAP=${KEYMAP:-us}
loadkeys "$KEYMAP"

# Disk Selection
lsblk -o NAME,SIZE,TYPE | grep disk
echo ""
read -p ":: Enter the disk to install to (e.g., /dev/sda or /dev/nvme0n1): " DISK
if [[ ! -b "$DISK" ]]; then
    error_exit "Disk $DISK does not exist."
fi

# Hostname
read -p ":: Enter hostname [default: arch]: " HOSTNAME
HOSTNAME=${HOSTNAME:-arch}

# Root Password
read -s -p ":: Enter root password: " ROOT_PASS
echo ""
read -s -p ":: Confirm root password: " ROOT_PASS_CONFIRM
echo ""
if [[ "$ROOT_PASS" != "$ROOT_PASS_CONFIRM" ]]; then
    error_exit "Passwords do not match."
fi

# User Creation
read -p ":: Enter username for regular user: " USERNAME
read -s -p ":: Enter password for $USERNAME: " USER_PASS
echo ""
read -s -p ":: Confirm password for $USERNAME: " USER_PASS_CONFIRM
echo ""
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    error_exit "Passwords do not match."
fi

# Confirm Installation
echo ""
echo "=========================================="
echo "   SUMMARY"
echo "=========================================="
echo "Target Disk:   $DISK"
echo "Hostname:      $HOSTNAME"
echo "Username:      $USERNAME"
echo "Kernel:        Linux (Liquorix)"
echo "Boot Mode:     UEFI"
echo "=========================================="
read -p ":: Ready to format disk and install? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation aborted."
    exit 0
fi

# ---------------------------------------------------------
# 2. PRE-INSTALL SETUP (Mirrors, Clock, Repos)
# ---------------------------------------------------------
echo ":: Updating System Clock..."
timedatectl set-ntp true

echo ":: Ranking Mirrors..."
pacman -Sy --noconfirm reflector
reflector --latest 20 --sort speed --save /etc/pacman.d/mirrorlist

echo ":: Setting up Chaotic-AUR (Live Environment)..."
# We need this NOW so your DankMaterialShell script can find the repo later.
# 1. Add the Repo to the Live ISO's pacman.conf
if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf
fi

# 2. Install the keyring and mirrorlist to the Live ISO
pacman -Sy --noconfirm chaotic-keyring chaotic-mirrorlist || {
    echo ":: Warning: Could not install chaotic-mirrorlist package. Falling back to direct download..."
    # Fallback: Download mirrorlist directly so we don't fail
    mkdir -p /etc/pacman.d
    curl -s 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist' -o /etc/pacman.d/chaotic-mirrorlist
}

# Sync Live ISO DB
pacman -Sy

# ---------------------------------------------------------
# 3. PARTITIONING
# ---------------------------------------------------------
echo ":: Partitioning $DISK..."
wipefs -a "$DISK" &>/dev/null
sgdisk -Z "$DISK"

sgdisk -n 0:0:+512M -t 0:ef00 -c 0:"EFI" "$DISK"
sgdisk -n 0:0:0 -t 0:8300 -c 0:"Linux" "$DISK"

if [[ "$DISK" =~ "nvme" ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

echo ":: Formatting..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo ":: Mounting..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ---------------------------------------------------------
# 4. BASE INSTALLATION
# ---------------------------------------------------------
echo ":: Installing Base System..."

pacstrap /mnt base base-devel linux-firmware \
    networkmanager wpa_supplicant \
    git curl wget vim man-db man-pages texinfo \
    bash-completion sudo efibootmgr grub os-prober

# ---------------------------------------------------------
# 5. CONFIGURATION
# ---------------------------------------------------------
echo ":: Generating Fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo ":: Configuring Locales..."
sed -i '/en_US\.UTF-8/s/^#//g' /mnt/etc/locale.gen
sed -i '/de_DE\.UTF-8/s/^#//g' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

# ---------------------------------------------------------
# 6. REPOS & KERNEL (Inside New System)
# ---------------------------------------------------------
echo ":: Configuring Repositories for new system..."

# 1. Enable Multilib
sed -i '/#\[multilib\]/,+1s/^#//' /mnt/etc/pacman.conf
sed -i '/^#ParallelDownloads/s/^#//' /mnt/etc/pacman.conf
sed -i '/^#Color/s/^#//' /mnt/etc/pacman.conf

# 2. Install Liquorix Kernel
mkdir -p /mnt/run/systemd/resolve/
cp /run/systemd/resolve/resolv.conf /mnt/run/systemd/resolve/resolv.conf
arch-chroot /mnt /bin/bash -c "curl -s 'https://liquorix.net/install-liquorix.sh' | bash"

# 3. Setup Chaotic-AUR in the NEW system
echo ":: Installing Chaotic-AUR to new system..."
# Install packages to the new system (/mnt)
pacman --root /mnt -Sy --noconfirm chaotic-keyring chaotic-mirrorlist

# Add the repo entry to the new system's pacman.conf
if ! grep -q "\[chaotic-aur\]" /mnt/etc/pacman.conf; then
    echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /mnt/etc/pacman.conf
fi

# Sync new system databases
pacman --root /mnt -Sy

# ---------------------------------------------------------
# 7. SYSTEM FINALIZATION
# ---------------------------------------------------------
echo ":: Finalizing System Settings..."

# Timezone
ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# Hostname
echo "$HOSTNAME" > /mnt/etc/hostname
cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Users & Passwords
echo "root:$ROOT_PASS" | arch-chroot /mnt chpasswd
arch-chroot /mnt useradd -m -G wheel,storage,power,audio,video -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | arch-chroot /mnt chpasswd
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /mnt/etc/sudoers

# Services
arch-chroot /mnt systemctl enable NetworkManager

# ---------------------------------------------------------
# 8. BOOTLOADER
# ---------------------------------------------------------
echo ":: Installing GRUB..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------
# 9. HARDWARE & PERFORMANCE
# ---------------------------------------------------------
echo ":: Installing Drivers & Tweaks..."

# CPU Microcode
CPU_VENDOR=$(lscpu | grep -m1 "Vendor ID" | awk '{print $3}')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    pacman --root /mnt -S --noconfirm intel-ucode
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    pacman --root /mnt -S --noconfirm amd-ucode
fi

# Firmware & Compatibility
pacman --root /mnt -S --noconfirm sof-firmware alsa-utils bluez bluez-utils cups \
    ntfs-3g exfatprogs

arch-chroot /mnt systemctl enable bluetooth cups

# Performance Tweaks
cat <<EOF > /mnt/etc/tmpfiles.d/ioscheduler.conf
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/scheduler}="mq-deadline"
EOF

cat <<EOF > /mnt/etc/sysctl.d/99-performance.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 50
kernel.watchdog = 0
EOF

sed -i 's/relatime/noatime/g' /mnt/etc/fstab

# Rebuild initramfs
echo ":: Rebuilding Initramfs..."
arch-chroot /mnt mkinitcpio -P

# Final GRUB update
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------
# 10. UNMOUNT
# ---------------------------------------------------------
echo ":: Unmounting..."
umount -R /mnt

echo "=========================================="
echo "   INSTALLATION COMPLETE"
echo "=========================================="
echo "System is ready. You can now run your DankMaterialShell script."
