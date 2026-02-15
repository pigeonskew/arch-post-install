#!/bin/bash

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# ---------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------
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
echo "Keyboard:      $KEYMAP"
echo "Kernel:        Linux (Liquorix)"
echo "Filesystem:    EXT4"
echo "Boot Mode:     UEFI"
echo "=========================================="
read -p ":: Ready to format disk and install? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation aborted."
    exit 0
fi

# ---------------------------------------------------------
# 2. SYSTEM CLOCK & PARTITIONING
# ---------------------------------------------------------
echo ":: Setting up system clock..."
timedatectl set-ntp true

echo ":: Partitioning $DISK..."
# Wipe disk
wipefs -a "$DISK"
sgdisk -Z "$DISK"

# Create partitions: 512MB EFI, Rest Linux
sgdisk -n 0:0:+512M -t 0:ef00 -c 0:"EFI" "$DISK"
sgdisk -n 0:0:0 -t 0:8300 -c 0:"Linux" "$DISK"

# Detect partition prefixes (e.g., sda1 vs nvme0n1p1)
if [[ "$DISK" =~ "nvme" ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

echo ":: Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"

echo ":: Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir /mnt/boot
mount "$EFI_PART" /mnt/boot

# ---------------------------------------------------------
# 3. REPOSITORIES & MIRRORS
# ---------------------------------------------------------
echo ":: Configuring Pacman & Mirrors..."
# Install reflector to get best mirrors
pacman -Sy --noconfirm reflector

# Backup existing mirrorlist
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

# Fetch latest mirrors (limit to 20 most recent, sort by speed)
reflector --latest 20 --sort speed --save /etc/pacman.d/mirrorlist

# Enable Multilib (32-bit support) and extra repos
sed -i '/#\[multilib\]/,+1s/^#//' /etc/pacman.conf
sed -i '/#\[extra\]/,+1s/^#//' /etc/pacman.conf

# Enable parallel downloads and color output
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Add Chaotic-AUR (extra repo for user convenience)
echo ":: Adding Chaotic-AUR..."
pacman-key --init
pacman -Sy --noconfirm chaotic-keyring
pacman -Sy --noconfirm chaotic-mirrorlist

# Add Chaotic repo to pacman.conf
echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf

# Sync databases
pacman -Sy

# ---------------------------------------------------------
# 4. BASE INSTALLATION
# ---------------------------------------------------------
echo ":: Installing base system packages..."
# Base packages + Linux API headers for compatibility
# Installing 'linux' and 'linux-headers' as a fallback/base for DKMS modules
pacstrap /mnt base base-devel linux linux-headers linux-firmware \
    networkmanager wpa_supplicant dialog wireless_tools \
    git curl wget vim man-db man-pages texinfo \
    bash-completion sudo archlinux-keyring \
    efibootmgr grub os-prober

# ---------------------------------------------------------
# 5. SYSTEM CONFIGURATION (CHROOT)
# ---------------------------------------------------------
echo ":: Configuring installed system..."

# Generate Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Set Timezone
ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /mnt/etc/localtime
arch-chroot /mnt hwclock --systohc

# Locales (English US and German DE as requested)
echo ":: Configuring Locales..."
sed -i '/en_US\.UTF-8/s/^#//g' /mnt/etc/locale.gen
sed -i '/de_DE\.UTF-8/s/^#//g' /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

# Network Configuration
echo "$HOSTNAME" > /mnt/etc/hostname
cat <<EOF > /mnt/etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

# Root Password
echo "root:$ROOT_PASS" | arch-chroot /mnt chpasswd

# User Creation
arch-chroot /mnt useradd -m -G wheel,storage,power,audio,video -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASS" | arch-chroot /mnt chpasswd

# Sudoers
sed -i '/^# %wheel ALL=(ALL:ALL) ALL/s/^# //' /mnt/etc/sudoers

# Enable NetworkManager
arch-chroot /mnt systemctl enable NetworkManager

# ---------------------------------------------------------
# 6. BOOTLOADER
# ---------------------------------------------------------
echo ":: Installing GRUB..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# ---------------------------------------------------------
# 7. HARDWARE COMPATIBILITY & PERFORMANCE
# ---------------------------------------------------------
echo ":: Installing Hardware Drivers & Compatibility Packages..."

# Microcode (detect CPU vendor)
CPU_VENDOR=$(cat /proc/cpuinfo | grep -m1 "vendor_id" | awk '{print $3}')
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    pacstrap /mnt intel-ucode
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    pacstrap /mnt amd-ucode
fi

# Essential Firmware & Compatibility
pacstrap /mnt sof-firmware alsa-utils alsa-plugins \
    cups bluez bluez-utils \
    ntfs-3g exfatprogs dosfstools mtools \
    bash-completion

# Enable Bluetooth and Printing services
arch-chroot /mnt systemctl enable bluetooth cups

echo ":: Installing Liquorix Kernel..."
# Use curl to fetch and run the install script inside the chroot
# We bind mount the host's resolve.conf to ensure networking works inside chroot if needed,
# though arch-chroot usually handles this.
# We use 'su -' to ensure environment variables are loaded.
arch-chroot /mnt /bin/bash -c "curl -s 'https://liquorix.net/install-liquorix.sh' | bash"

# Update GRUB to detect Liquorix
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo ":: Applying Performance Tweaks..."

# 1. I/O Schedulers: Set 'mq-deadline' or 'bfq' for better responsiveness
# Creating a tmpfile rule for systemd
cat <<EOF > /mnt/etc/tmpfiles.d/ioscheduler.conf
# Set I/O scheduler for SSDs and HDDs
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]n[0-9]", ATTR{queue/scheduler}="mq-deadline"
EOF

# 2. Sysctl tweaks: Swappiness, Cache Pressure, and Watchdog
cat <<EOF > /mnt/etc/sysctl.d/99-performance.conf
# Reduce swap usage (default 60)
vm.swappiness = 10

# Increase cache pressure (reclaim inode/dentry cache faster)
vm.vfs_cache_pressure = 50

# Improve kernel responsiveness by reducing watchdog overhead
kernel.watchdog = 0

# Allow somewhat aggressive file pre-allocation
fs.prealoc_enforce = 0
EOF

# 3. Filesystem mount options (add 'noatime' to fstab for root partition)
# This reduces disk writes by not updating access times on every read
sed -i 's/relatime/noatime/g' /mnt/etc/fstab

# ---------------------------------------------------------
# 8. CLEANUP
# ---------------------------------------------------------
echo ":: Unmounting and finishing..."
umount -R /mnt

echo "=========================================="
echo "   INSTALLATION COMPLETE"
echo "=========================================="
echo "System installed successfully."
echo "You may now reboot."
echo ""
echo "Note: Don't forget to install your custom shell (e.g., DankMaterialShell)."
