#!/bin/bash
# MangoWC + Noctalia Shell Installation Script for Arch Linux
# Run this after base Arch installation (no DE/shell)
# Updated for enhanced hardware/software compatibility

set -e  # Exit on error

echo "=========================================="
echo "  MangoWC + Noctalia Shell Installer"
echo "  (Enhanced Compatibility Edition)"
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

# Keep sudo timestamp updated
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null & done 2>/dev/null &

echo ""
echo "[0/6] Enabling necessary repositories (multilib)..."
# Enable multilib repo for broader software compatibility (Steam, proprietary apps)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling [multilib] repository..."
    sudo sed -i '/^\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
else
    echo "[multilib] repository already enabled."
fi

echo ""
echo "[1/6] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[2/6] Installing AUR helper (yay)..."
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
echo "[3/6] Installing Hardware Compatibility Packages..."
# Firmware, Audio, Network, Bluetooth, Graphics, XWayland
sudo pacman -S --needed --noconfirm \
    linux-firmware \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    networkmanager network-manager-applet \
    bluez bluez-utils \
    mesa vulkan-radeon vulkan-intel vulkan-tools \
    xorg-xwayland \
    libinput xf86-input-libinput

echo ""
echo "[4/6] Installing Desktop Utilities & Fonts..."
# Polkit, Clipboard, Notifications, Terminal, Launcher, Fonts, Screen Lock
sudo pacman -S --needed --noconfirm \
    polkit-gnome \
    cliphist wl-clipboard \
    mako \
    foot \
    wmenu \
    grim slurp \
    swaylock \
    noto-fonts ttf-font-awesome gnu-free-fonts \
    xdg-user-dirs

# Enable essential services
echo ""
echo "Enabling system services (NetworkManager, Bluetooth)..."
sudo systemctl enable NetworkManager
sudo systemctl enable bluetooth

echo ""
echo "[5/6] Installing MangoWC..."
yay -S --needed --noconfirm mangowc-git

echo ""
echo "[6/6] Installing Noctalia Shell..."
yay -S --needed --noconfirm noctalia-shell

echo ""
echo "=========================================="
echo "  Configuring MangoWC and Noctalia..."
echo "=========================================="

# Create config directories
mkdir -p ~/.config/mango
mkdir -p ~/.config/quickshell/noctalia-shell
mkdir -p ~/.config/mako

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

# Screenshot bindings
bind=SUPER,Print,exec,grim -g "$(slurp)" - | wl-copy
bind=,Print,exec,grim - | wl-copy
EOF
fi

# Create MangoWC autostart script for Noctalia integration
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash
# Audio
pipewire &
wireplumber &

# Notifications
mako &

# Authentication Agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Clipboard
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# Shell
qs -c noctalia-shell &

# Environment variables for GTK/Qt apps
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots

# Screen lock idle (optional, requires swayidle if added)
# swayidle -w timeout 300 'swaylock -f -c 000000' timeout 600 'mangoctl output power off' resume 'mangoctl output power on'
EOF

chmod +x ~/.config/mango/autostart.sh

# Create basic Mako config for notifications
if [ ! -f ~/.config/mako/config ]; then
    cat > ~/.config/mako/config << 'EOF'
background-color=#285577
text-color=#ffffff
width=300
height=100
margin=10
padding=10
border-size=2
border-color=#4488bb
font=Sans 12
EOF
fi

# Ensure autostart is in config
if [ -f ~/.config/mango/config.conf ]; then
    if ! grep -q "exec-once=.*autostart.sh" ~/.config/mango/config.conf; then
        echo "" >> ~/.config/mango/config.conf
        echo "# Autostart script" >> ~/.config/mango/config.conf
        echo "exec-once=~/.config/mango/autostart.sh" >> ~/.config/mango/config.conf
    fi
fi

# Generate XDG directories
xdg-user-dirs-update

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Please reboot your system now."
echo "After reboot, start the desktop by running: mango"
echo ""
echo "Hardware & Software Improvements Added:"
echo "  - Multilib repo enabled"
echo "  - Firmware & Microcode support"
echo "  - PipeWire Audio Stack"
echo "  - NetworkManager & Bluetooth"
echo "  - Vulkan & Mesa Graphics"
echo "  - XWayland for X11 app support"
echo "  - Fonts & Clipboard Manager"
echo ""
echo "Trackpad settings configured in: ~/.config/mango/config.conf"
echo "  - tap_to_click enabled"
echo "  - natural_scrolling enabled"
echo ""
