#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# Verify UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "This script requires a UEFI system."
    exit 1
fi

# --- Helper Functions ---
verify_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        echo "You must run this script from an Arch Linux live environment."
        exit 1
    fi
}

set_keyboard() {
    echo "Available keymaps:"
    localectl list-keymaps | less
    read -rp "Enter keyboard layout (e.g., us, de): " KEYMAP
    loadkeys "$KEYMAP"
}

connect_wifi() {
    read -rp "Do you want to connect to Wi-Fi? (y/n): " WIFI_CHOICE
    if [[ "$WIFI_CHOICE" == "y" ]]; then
        iwctl
    fi
    # Check connection
    if ! ping -c 1 archlinux.org &> /dev/null; then
        echo "No internet connection. Exiting."
        exit 1
    fi
}

# --- Installation Logic ---
main() {
    verify_arch
    set_keyboard
    connect_wifi

    # Disk Setup
    lsblk
    read -rp "Enter the disk to install to (e.g., /dev/nvme0n1 or /dev/sda): " DISK
    
    # Validation to prevent accidental system destruction
    if [[ ! -b "$DISK" ]]; then
        echo "Disk $DISK not found."
        exit 1
    fi

    echo "WARNING: All data on $DISK will be wiped!"
    read -rp "Type 'YES' to confirm partitioning: " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
        exit 1
    fi

    # Partitioning (UEFI)
    # 1: 512M EFI System Partition
    # 2: Remainder Linux Filesystem (Root)
    echo "Partitioning disk..."
    parted "$DISK" --script mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart root ext4 513MiB 100%

    # Formatting
    echo "Formatting partitions..."
    mkfs.fat -F32 "${DISK}p1" 2>/dev/null || mkfs.fat -F32 "${DISK}1"
    
    # We use BTRFS for performance features (compression), or ext4 for simplicity.
    # Request asked for performance tweaks. BTRFS with zstd is a good standard.
    read -rp "Use BTRFS for root? (Recommended for performance/snapshots) (y/n): " FS_CHOICE
    if [[ "$FS_CHOICE" == "y" ]]; then
        FS_TYPE="btrfs"
        mkfs.btrfs -f "${DISK}p2" 2>/dev/null || mkfs.btrfs -f "${DISK}2"
    else
        FS_TYPE="ext4"
        mkfs.ext4 -F "${DISK}p2" 2>/dev/null || mkfs.ext4 -F "${DISK}2"
    fi

    # Mounting
    mount "${DISK}p2" /mnt 2>/dev/null || mount "${DISK}2" /mnt
    mkdir -p /mnt/boot
    mount "${DISK}p1" /mnt/boot 2>/dev/null || mount "${DISK}1" /mnt/boot

    # Base Installation
    echo "Installing base system..."
    pacstrap /mnt base base-devel linux-firmware git vim networkmanager intel-ucode amd-ucode

    # Generate Fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # Timezone & Clock
    read -rp "Enter Timezone (e.g., America/New_York): " TIMEZONE
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locales (Max 2)
    echo "Configuring locales..."
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    read -rp "Enter a second locale (e.g., de_DE.UTF-8) or press Enter to skip: " LOC2
    if [[ -n "$LOC2" ]]; then
        echo "$LOC2 UTF-8" >> /mnt/etc/locale.gen
    fi
    arch-chroot /mnt locale-gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf

    # Hostname & Hosts
    read -rp "Enter hostname: " HOSTNAME
    echo "$HOSTNAME" > /mnt/etc/hostname
    echo "127.0.0.1   localhost" > /mnt/etc/hosts
    echo "::1         localhost" >> /mnt/etc/hosts
    echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /mnt/etc/hosts

    # User Setup
    read -rp "Enter root password: " ROOTPASS
    arch-chroot /mnt echo "root:$ROOTPASS" | chpasswd

    read -rp "Enter username: " USERNAME
    arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash "$USERNAME"
    read -rp "Enter user password: " USERPASS
    arch-chroot /mnt echo "$USERNAME:$USERPASS" | chpasswd
    
    # Sudoers setup
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

    # --- Performance & Compatibility Setup ---
    
    echo "Installing Liquorix Kernel..."
    # Install dependencies first
    arch-chroot /mnt pacman -S --noconfirm curl
    # Run the Liquorix install script as requested
    arch-chroot /mnt bash -c "curl -s 'https://liquorix.net/install-liquorix.sh' | bash"

    echo "Installing essential packages for hardware compatibility..."
    # Essential Firmware
    arch-chroot /mnt pacman -S --noconfirm --needed \
        linux-firmware \
        sof-firmware \
        bluez \
        bluez-utils \
        cups \
        avahi \
        xdg-utils \
        gvfs \
        gvfs-mtp \
        udisks2 \
        ntfs-3g \
        exfatprogs \
        bash-completion

    # Performance Tweaks
    echo "Applying performance tweaks..."
    # I/O Scheduler (BFQ for SSDs/HDDs responsiveness)
    cat <<EOF > /mnt/etc/udev/rules.d/60-ioschedulers.rules
# Set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
# Set scheduler for SSDs and HDDs
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/scheduler}="bfq"
EOF

    # Enable services
    arch-chroot /mnt systemctl enable NetworkManager systemd-resolved
    arch-chroot /mnt systemctl enable bluetooth cups avahi-daemon

    # --- Limine Bootloader Setup ---
    echo "Installing Limine..."
    arch-chroot /mnt pacman -S --noconfirm limine

    # Limine installation logic
    # Note: Limine setup can vary; this installs the binaries to the ESP and creates a basic config.
    # We assume the ESP is mounted at /boot.
    
    # Install Limine to the EFI partition
    arch-chroot /mnt limine-install "$DISK"

    # Detect Microcode
    UCODE_INITRD=""
    if [[ -f /mnt/boot/intel-ucode.img ]]; then
        UCODE_INITRD="initrd=/intel-ucode.img"
    elif [[ -mnt/boot/amd-ucode.img ]]; then
        UCODE_INITRD="initrd=/amd-ucode.img"
    fi

    # Get Root UUID
    ROOT_UUID=$(blkid -s UUID -o value "${DISK}p2" 2>/dev/null || blkid -s UUID -o value "${DISK}2")

    # Create Limine Configuration
    # Limine looks for limine.conf in the root of the ESP or /boot
    cat <<EOF > /mnt/boot/limine.conf
timeout: 5

/Arch Linux Liquorix
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-lqx
    kernel_cmdline: root=UUID=$ROOT_UUID rw $UCODE_INITRD initrd=/initramfs-linux-lqx.img quiet
EOF

    echo "Installation complete."
    echo "You may now reboot into your new system."
}

main
