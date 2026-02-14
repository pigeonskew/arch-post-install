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
    read -rp "Enter keyboard layout (e.g., us, de): " KEYMAP
    loadkeys "$KEYMAP"
}

connect_wifi() {
    read -rp "Do you want to connect to Wi-Fi? (y/n): " WIFI_CHOICE
    if [[ "$WIFI_CHOICE" == "y" ]]; then
        iwctl
    fi
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
    echo "Partitioning disk..."
    parted "$DISK" --script mklabel gpt \
        mkpart ESP fat32 1MiB 513MiB \
        set 1 esp on \
        mkpart root ext4 513MiB 100%

    # Define partition names
    if [[ "$DISK" =~ "nvme" ]]; then
        BOOT_PART="${DISK}p1"
        ROOT_PART="${DISK}p2"
    else
        BOOT_PART="${DISK}1"
        ROOT_PART="${DISK}2"
    fi

    # Formatting
    echo "Formatting partitions..."
    mkfs.fat -F32 "$BOOT_PART"
    
    read -rp "Use BTRFS for root? (Recommended for performance) (y/n): " FS_CHOICE
    if [[ "$FS_CHOICE" == "y" ]]; then
        FS_TYPE="btrfs"
        mkfs.btrfs -f "$ROOT_PART"
    else
        FS_TYPE="ext4"
        mkfs.ext4 -F "$ROOT_PART"
    fi

    # Mounting
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot

    # Base Installation
    echo "Installing base system..."
    pacstrap /mnt base base-devel linux-firmware git vim networkmanager intel-ucode amd-ucode efibootmgr

    # Generate Fstab
    genfstab -U /mnt >> /mnt/etc/fstab

    # Timezone & Clock
    read -rp "Enter Timezone (e.g., America/New_York): " TIMEZONE
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Locales
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
    
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/wheel

    # --- Performance & Compatibility ---
    
    echo "Installing Liquorix Kernel..."
    arch-chroot /mnt pacman -S --noconfirm curl
    arch-chroot /mnt bash -c "curl -s 'https://liquorix.net/install-liquorix.sh' | bash"

    echo "Installing essential packages..."
    arch-chroot /mnt pacman -S --noconfirm --needed \
        linux-firmware sof-firmware bluez bluez-utils cups avahi \
        xdg-utils gvfs gvfs-mtp udisks2 ntfs-3g exfatprogs bash-completion

    # I/O Scheduler Tweaks
    cat <<EOF > /mnt/etc/udev/rules.d/60-ioschedulers.rules
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/scheduler}="bfq"
EOF

    arch-chroot /mnt systemctl enable NetworkManager systemd-resolved
    arch-chroot /mnt systemctl enable bluetooth cups avahi-daemon

    # --- Limine Bootloader Setup ---
    echo "Installing Limine..."
    arch-chroot /mnt pacman -S --noconfirm limine

    # Install Limine to the disk
    arch-chroot /mnt limine-install "$DISK"

    # Detect Microcode
    UCODE_INITRD=""
    if [[ -f /mnt/boot/intel-ucode.img ]]; then
        UCODE_INITRD="initrd=/intel-ucode.img"
    elif [[ -f /mnt/boot/amd-ucode.img ]]; then
        UCODE_INITRD="initrd=/amd-ucode.img"
    fi

    # Get Root UUID
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

    # Create Limine Configuration
    cat <<EOF > /mnt/boot/limine.conf
timeout: 5

/Arch Linux Liquorix
    protocol: linux
    kernel_path: boot():/vmlinuz-linux-lqx
    kernel_cmdline: root=UUID=$ROOT_UUID rw $UCODE_INITRD initrd=/initramfs-linux-lqx.img quiet
EOF

    # --- FIX: Setup EFI Fallback Path ---
    # This ensures the system boots even if NVRAM entry is ignored
    echo "Setting up EFI fallback path..."
    mkdir -p /mnt/boot/EFI/BOOT
    cp /mnt/boot/limine-uefix64.efi /mnt/boot/EFI/BOOT/BOOTX64.EFI

    # Register in NVRAM
    echo "Registering Limine in UEFI..."
    if [[ "$DISK" =~ "nvme" ]]; then
        EFI_DISK="${DISK%p*}"
        PART_NUM="${BOOT_PART##*p}"
    else
        EFI_DISK="$DISK"
        PART_NUM="${BOOT_PART##*[a-z]}"
    fi

    # Remove old entry if exists
    BOOT_ENTRY_NUM=$(efibootmgr | grep "Limine" | sed 's/Boot\([0-9]*\)\*.*/\1/')
    if [[ -n "$BOOT_ENTRY_NUM" ]]; then
        efibootmgr -b "$BOOT_ENTRY_NUM" -B
    fi

    efibootmgr --create --disk "$EFI_DISK" --part "$PART_NUM" --loader /limine-uefix64.efi --label "Limine"

    echo "Installation complete. Rebooting should now load Limine correctly."
}

main
