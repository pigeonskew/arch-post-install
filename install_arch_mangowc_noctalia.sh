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
echo "[1/5] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[2/5] Installing AUR helper (yay)..."
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
echo "[3/5] Installing libinput for trackpad support..."
sudo pacman -S --needed --noconfirm libinput xf86-input-libinput

echo ""
echo "[4/5] Installing MangoWC..."
echo "This will also automatically install wlroots-git and scenefx-git as dependencies."
yay -S --needed --noconfirm mangowc-git

echo ""
echo "[5/5] Installing Noctalia Shell and essential desktop applications..."
yay -S --needed --noconfirm noctalia-shell brightnessctl imagemagick python ddcutil cliphist cava wlsunset xdg-desktop-portal xdg-desktop-portal-wlr evolution-data-server
yay -S --needed --noconfirm foot wmenu wl-clipboard grim slurp swaybg mako libnotify polkit-gnome bemenu fuzzel pipewire wireplumber ttf-jetbrains-mono-nerd noto-fonts

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
EOF
fi

# Create MangoWC autostart script for Noctalia integration
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash
pipewire &
wireplumber &
mako &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &
qs -c noctalia-shell &
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
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

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "Start the desktop by running: mango"
echo ""
echo "Trackpad settings configured in: ~/.config/mango/config.conf"
echo "  - tap_to_click enabled"
echo "  - natural_scrolling enabled"
echo ""
