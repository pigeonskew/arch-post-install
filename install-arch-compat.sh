#!/bin/bash

# Arch Linux Automated Installation Script
# For maximum software/hardware compatibility and performance

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/tmp/arch_install_$(date +%Y%m%d_%H%M%S).log"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
    echo "$(date): $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
    echo "$(date): ERROR: $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[*]${NC} $1"
    echo "$(date): WARNING: $1" >> "$LOG_FILE"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root"
    exit 1
fi

# Check if running in Arch ISO
if [ ! -f /etc/arch-release ]; then
    print_error "This script must be run from Arch Linux ISO"
    exit 1
fi

# Welcome message
clear
print_status "Arch Linux Automated Installation Script"
print_status "Log file: $LOG_FILE"
echo ""

# Get user input
read -p "Enter hostname: " HOSTNAME
read -p "Enter username: " USERNAME
read -s -p "Enter password for $USERNAME: " PASSWORD
echo ""
read -s -p "Confirm password: " PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    print_error "Passwords do not match"
    exit 1
fi

# Select disk
print_status "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
read -p "Enter disk to install to (e.g., sda): " DISK

# Update system clock
print_status "Updating system clock"
timedatectl set-ntp true >> "$LOG_FILE" 2>&1

# Partition disk
print_status "Partitioning $DISK"
if [[ "$DISK" == *"nvme"* ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

# Wipe disk and create partitions
sgdisk -Z "/dev/$DISK" >> "$LOG_FILE" 2>&1
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "/dev/$DISK" >> "$LOG_FILE" 2>&1
sgdisk -n 2:0:+8G -t 2:8200 -c 2:"SWAP" "/dev/$DISK" >> "$LOG_FILE" 2>&1
sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "/dev/$DISK" >> "$LOG_FILE" 2>&1

# Format partitions
print_status "Formatting partitions"
mkfs.fat -F32 "/dev/${PART_PREFIX}1" >> "$LOG_FILE" 2>&1
mkswap "/dev/${PART_PREFIX}2" >> "$LOG_FILE" 2>&1
mkfs.ext4 -F "/dev/${PART_PREFIX}3" >> "$LOG_FILE" 2>&1

# Mount partitions
print_status "Mounting partitions"
mount "/dev/${PART_PREFIX}3" /mnt >> "$LOG_FILE" 2>&1
mkdir -p /mnt/boot >> "$LOG_FILE" 2>&1
mount "/dev/${PART_PREFIX}1" /mnt/boot >> "$LOG_FILE" 2>&1
swapon "/dev/${PART_PREFIX}2" >> "$LOG_FILE" 2>&1

# Install base system
print_status "Installing base system"
pacstrap /mnt base base-devel linux-firmware >> "$LOG_FILE" 2>&1

# Generate fstab
print_status "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot and configure
print_status "Configuring system"

cat > /mnt/root/setup.sh << 'EOF'
#!/bin/bash

# Time zone
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m -G wheel,audio,video,optical,storage,input "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Sudo configuration
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers

# Pacman configuration
sed -i 's/#Color/Color/' /etc/pacman.conf
sed -i 's/#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
echo "ILoveCandy" >> /etc/pacman.conf

# Enable multilib
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
sed -i 's/#\[multilib\]/\[multilib\]/' /etc/pacman.conf
sed -i 's/#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/' /etc/pacman.conf

# Systemd-boot installation
bootctl --path=/boot install

# Create boot entry
cat > /boot/loader/entries/arch.conf << BOOT
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/${PART_PREFIX}3) rw
BOOT

# Default boot entry
echo "default arch.conf" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf

# Update packages
pacman -Syyu --noconfirm

# Install essential packages
pacman -S --noconfirm \
    networkmanager \
    network-manager-applet \
    git \
    curl \
    wget \
    htop \
    neovim \
    tmux \
    openssh \
    firewalld \
    ufw \
    fwupd \
    ntfs-3g \
    exfat-utils \
    dosfstools \
    mtools \
    xdg-user-dirs \
    xdg-utils \
    polkit \
    polkit-gnome \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    openssl \
    ca-certificates \
    reflector \
    mesa \
    mesa-demos \
    vulkan-intel \
    vulkan-radeon \
    vulkan-icd-loader \
    lib32-mesa \
    lib32-vulkan-intel \
    lib32-vulkan-radeon \
    lib32-vulkan-icd-loader \
    xf86-video-intel \
    xf86-video-amdgpu \
    xf86-video-nouveau \
    xf86-video-ati \
    xf86-video-vmware \
    xf86-input-libinput \
    bluez \
    bluez-utils \
    pulseaudio-bluetooth \
    cups \
    hplip \
    sane \
    tlp \
    tlp-rdw \
    powertop \
    thermald \
    irqbalance \
    preload \
    earlyoom \
    ananicy-cpp \
    uksmd \
    zram-generator \
    fstrim \
    man-db \
    man-pages \
    texinfo \
    flatpak \
    snapd \
    docker \
    docker-compose \
    podman \
    buildah \
    virtualbox-guest-utils \
    qemu-guest-agent \
    spice-vdagent \
    dmidecode \
    lm_sensors \
    smartmontools \
    hddtemp \
    nvme-cli \
    pciutils \
    usbutils \
    sysfsutils \
    cpupower \
    tuned \
    tuned-utils \
    schedtool \
    schedtool-dl \
    linux-zen-headers \
    dkms \
    acpi \
    acpid \
    acpi_call \
    cpio \
    bc \
    kernel-modules-hook \
    nftables

# Install GPU monitoring tools
pacman -S --noconfirm \
    radeontop \
    intel-gpu-tools \
    nvtop

# Install Liquorix kernel
curl -s 'https://liquorix.net/install-liquorix.sh' | bash

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups
systemctl enable tlp
systemctl enable fstrim.timer
systemctl enable thermald
systemctl enable irqbalance
systemctl enable earlyoom
systemctl enable ananicy-cpp
systemctl enable uksmd
systemctl enable docker
systemctl enable snapd
systemctl enable fwupd
systemctl enable systemd-boot-update
systemctl enable acpid
systemctl enable nftables

# Optimize sysctl
cat > /etc/sysctl.d/99-performance.conf << SYSCTL
# Improve memory management
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
vm.max_map_count=1048576

# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Kernel optimizations
kernel.numa_balancing=0
kernel.sched_autogroup_enabled=0
kernel.sched_min_granularity_ns=10000000
kernel.sched_wakeup_granularity_ns=15000000
SYSCTL

# CPU governor
cat > /etc/udev/rules.d/64-cpu-governor.rules << UDEV
SUBSYSTEM=="cpu", ACTION=="add", KERNEL=="cpu[0-9]*", RUN+="/usr/bin/sh -c 'echo performance > /sys/devices/system/cpu/cpu%/cpufreq/scaling_governor'"
UDEV

# Create zram swap
cat > /etc/systemd/zram-generator.conf << ZRAM
[zram0]
zram-size = ram * 2
compression-algorithm = zstd
ZRAM

# Docker configuration
cat > /etc/docker/daemon.json << DOCKER
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DOCKER

# Add user to groups
usermod -aG docker,disk,lp,wheel,audio,video,optical,storage,kvm,libvirt "$USERNAME"

# Update initramfs
mkinitcpio -P

EOF

# Copy variables and execute setup in chroot
chmod +x /mnt/root/setup.sh
arch-chroot /mnt /bin/bash -c "HOSTNAME=$HOSTNAME USERNAME=$USERNAME PASSWORD=$PASSWORD PART_PREFIX=$PART_PREFIX /root/setup.sh" >> "$LOG_FILE" 2>&1

# Cleanup
rm /mnt/root/setup.sh

# Unmount
print_status "Unmounting partitions"
umount -R /mnt >> "$LOG_FILE" 2>&1

print_status "Installation complete!"
print_status "You can now reboot into your new Arch Linux system"
print_status "After reboot, install your preferred shell (e.g., DankMaterialShell)"

# Optional: Reboot
read -p "Reboot now? (y/N): " REBOOT
if [[ "$REBOOT" =~ ^[Yy]$ ]]; then
    reboot
fi
