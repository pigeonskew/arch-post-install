#!/bin/bash
# MangoWC + Noctalia Shell Installation Script for Arch Linux
# Run this after base Arch installation (no DE/shell)

set -e  # Exit on error

echo "=========================================="
echo "  MangoWC + Noctalia Shell Installer"
echo "=========================================="

# Check if running as root (we don't want that for AUR helpers)
if [ "$EUID" -eq 0 ]; then 
   echo "Please do not run this script as root."
   echo "AUR helpers should not be run as root."
   exit 1
fi

# Check for sudo access
if ! sudo -v; then
    echo "This script requires sudo privileges."
    exit 1
fi

echo ""
echo "[1/7] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[2/7] Installing AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    cd /tmp
    rm -rf yay
    git clone https://aur.archlinux.org/yay.git 
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay
else
    echo "yay already installed, skipping..."
fi

echo ""
echo "[3/7] Installing input drivers (trackpad, mouse, keyboard)..."
sudo pacman -S --needed --noconfirm \
    libinput \
    xf86-input-libinput \
    xf86-input-evdev \
    xf86-input-synaptics \
    xf86-input-wacom \
    xf86-input-vmmouse

echo ""
echo "[4/7] Installing graphics drivers and hardware acceleration..."
# Detect GPU and install appropriate drivers
if lspci | grep -i "nvidia" &> /dev/null; then
    echo "NVIDIA GPU detected..."
    sudo pacman -S --needed --noconfirm \
        nvidia-dkms \
        nvidia-utils \
        lib32-nvidia-utils \
        nvidia-settings \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        egl-wayland
elif lspci | grep -i "amd" &> /dev/null; then
    echo "AMD GPU detected..."
    sudo pacman -S --needed --noconfirm \
        mesa \
        lib32-mesa \
        vulkan-radeon \
        lib32-vulkan-radeon \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        libva-mesa-driver \
        lib32-libva-mesa-driver \
        mesa-vdpau \
        lib32-mesa-vdpau
elif lspci | grep -i "intel" &> /dev/null; then
    echo "Intel GPU detected..."
    sudo pacman -S --needed --noconfirm \
        mesa \
        lib32-mesa \
        vulkan-intel \
        lib32-vulkan-intel \
        vulkan-icd-loader \
        lib32-vulkan-icd-loader \
        intel-media-driver \
        libva-intel-driver \
        libvdpau-va-gl
fi

# Common graphics utilities
sudo pacman -S --needed --noconfirm \
    mesa-utils \
    libva-utils \
    vulkan-tools \
    wayland-utils \
    xorg-xwayland \
    egl-wayland \
    libdrm

echo ""
echo "[5/7] Installing audio system (PipeWire + Bluetooth)..."
sudo pacman -S --needed --noconfirm \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    alsa-utils \
    alsa-plugins \
    pavucontrol \
    pamixer \
    bluez \
    bluez-utils \
    blueman \
    pipewire-audio \
    pipewire-bluetooth \
    lib32-pipewire \
    lib32-pipewire-jack

# Enable Bluetooth service
sudo systemctl enable --now bluetooth

echo ""
echo "[6/7] Installing networking and connectivity tools..."
sudo pacman -S --needed --noconfirm \
    network-manager-applet \
    nm-connection-editor \
    iwd \
    wireless_tools \
    wpa_supplicant \
    dhcpcd \
    openresolv \
    avahi \
    nss-mdns \
    cups \
    cups-pdf \
    system-config-printer \
    usbutils \
    pciutils \
    lshw \
    dmidecode

# Enable services
sudo systemctl enable --now avahi-daemon
sudo systemctl enable --now cups.socket

echo ""
echo "[7/7] Installing essential system utilities and firmware..."
sudo pacman -S --needed --noconfirm \
    # Power management
    tlp \
    tlp-rdw \
    powertop \
    acpi \
    acpid \
    thermald \
    upower \
    # Firmware updates
    fwupd \
    # Disk utilities
    udisks2 \
    gvfs \
    gvfs-mtp \
    gvfs-gphoto2 \
    gvfs-afc \
    gvfs-smb \
    ntfs-3g \
    exfat-utils \
    dosfstools \
    e2fsprogs \
    btrfs-progs \
    # Hardware monitoring
    lm_sensors \
    htop \
    btop \
    # Security/Policy
    polkit \
    polkit-gnome \
    gnome-keyring \
    libsecret \
    # Notifications and clipboard
    mako \
    libnotify \
    wl-clipboard \
    cliphist \
    # Screenshots and screenlock
    grim \
    slurp \
    swappy \
    swaylock \
    swayidle \
    # Fonts and themes
    noto-fonts \
    noto-fonts-emoji \
    noto-fonts-cjk \
    ttf-dejavu \
    ttf-liberation \
    ttf-font-awesome \
    # File management
    nautilus \
    xdg-utils \
    xdg-user-dirs \
    # Terminal and editor
    foot \
    vim \
    nano \
    # Image and media
    imv \
    mpv \
    ffmpeg \
    ffmpegthumbnailer \
    # Archive tools
    p7zip \
    unzip \
    unrar \
    zip \
    tar \
    # System info
    neofetch \
    fastfetch \
    # Brightness control
    brightnessctl \
    # Screenshot/screen recording
    wf-recorder \
    # Color management
    colord \
    # Time synchronization
    ntp

# Install microcode updates
if grep -q "GenuineIntel" /proc/cpuinfo; then
    echo "Installing Intel microcode..."
    sudo pacman -S --needed --noconfirm intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    echo "Installing AMD microcode..."
    sudo pacman -S --needed --noconfirm amd-ucode
fi

# Enable power management services
sudo systemctl enable --now tlp
sudo systemctl enable --now acpid
sudo systemctl enable --now thermald

echo ""
echo "[8/8] Installing MangoWC and Noctalia Shell..."
yay -S --needed --noconfirm mangowc-git
yay -S --needed --noconfirm noctalia-shell

echo ""
echo "=========================================="
echo "  Configuring MangoWC and Noctalia..."
echo "=========================================="

# Create config directories
mkdir -p ~/.config/mango
mkdir -p ~/.config/quickshell/noctalia-shell

# Create minimal MangoWC config with trackpad support
if [ ! -f ~/.config/mango/config.conf ]; then
    echo "Creating minimal MangoWC config..."
    cat > ~/.config/mango/config.conf << 'EOF'
# Minimal MangoWC Configuration

# Input configuration for trackpad
[input]
accel_profile=flat
accel_speed=0.0
tap_to_click=1
natural_scrolling=1

# Autostart script
exec-once=~/.config/mango/autostart.sh

# Basic keybindings
bind=SUPER,Return,exec,foot
bind=SUPER,Q,kill
bind=SUPER,M,exit
bind=SUPER,Space,exec,wmenu-run
bind=SUPER,1,view,1
bind=SUPER,2,view,2
bind=SUPER,3,view,3
bind=SUPER,4,view,4
bind=SUPER,5,view,5

# Brightness keys
bind=,XF86MonBrightnessUp,exec,brightnessctl set +5%
bind=,XF86MonBrightnessDown,exec,brightnessctl set 5%-

# Volume keys
bind=,XF86AudioRaiseVolume,exec,pamixer -i 5
bind=,XF86AudioLowerVolume,exec,pamixer -d 5
bind=,XF86AudioMute,exec,pamixer -t

# Media keys
bind=,XF86AudioPlay,exec,playerctl play-pause
bind=,XF86AudioNext,exec,playerctl next
bind=,XF86AudioPrev,exec,playerctl previous

# Screenshot
bind=SUPER,Print,exec,grim -g "$(slurp)" - | swappy -f -
bind=,Print,exec,grim - | swappy -f -

# Lock screen
bind=SUPER,L,exec,swaylock -f -c 000000
EOF
fi

# Create MangoWC autostart script for Noctalia integration
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash

# Start PipeWire and session manager
pipewire &
wireplumber &

# Notification daemon
mako &

# Policy kit authentication agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Clipboard history
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# Network manager applet
nm-applet --indicator &

# Bluetooth applet
blueman-applet &

# Noctalia Shell
qs -c noctalia-shell &

# Update environment for systemd
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots

# Start idle management
swayidle -w \
    timeout 300 'swaylock -f -c 000000' \
    timeout 600 'mango dispatch dpms off' \
    resume 'mango dispatch dpms on' \
    before-sleep 'swaylock -f -c 000000' &
EOF

chmod +x ~/.config/mango/autostart.sh

# Ensure autostart is in config
if [ -f ~/.config/mango/config.conf ]; then
    if ! grep -q "exec-once=.*autostart.sh" ~/.config/mango/config.conf; then
        echo "" >> ~/.config/mango/config.conf
        echo "# Autostart script" >> ~/.config/mango/config.conf
        echo "exec-once=~/.config/mango/autostart.sh" >> ~/.config/mango/config.conf
    fi
fi

# Setup user directories
xdg-user-dirs-update

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Start the desktop by running: mango"
echo ""
echo "Configuration files:"
echo "  - MangoWC: ~/.config/mango/config.conf"
echo "  - Autostart: ~/.config/mango/autostart.sh"
echo ""
echo "Key features enabled:"
echo "  - Auto-detected GPU drivers (NVIDIA/AMD/Intel)"
echo "  - PipeWire audio with Bluetooth support"
echo "  - Power management (TLP) and thermal control"
echo "  - NetworkManager and Bluetooth applets"
echo "  - Clipboard history, notifications, screen lock"
echo "  - Brightness and volume media keys"
echo "  - Printer support (CUPS)"
echo "  - Firmware updates (fwupd)"
echo ""
echo "Post-install recommendations:"
echo "  1. Reboot to load all drivers: sudo reboot"
echo "  2. Run 'sudo sensors-detect' to setup hardware monitoring"
echo "  3. Configure TLP: sudo systemctl edit tlp (if on laptop)"
echo "  4. Add user to additional groups if needed:"
echo "     sudo usermod -aG video,audio,input,lp,scanner $USER"
