#!/bin/bash
# MangoWC + Noctalia Shell Installation Script for Arch Linux (FIXED v3)
# Run this after base Arch installation (no DE/shell)

set -e  # Exit on error

echo "=========================================="
echo "  MangoWC + Noctalia Shell Installer"
echo "  (Fixed for scenefx-git dependency)"
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
echo "[1/8] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[2/8] Installing AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    cd /tmp
    rm -rf yay  # Clean up any previous attempts
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay
else
    echo "yay already installed, skipping..."
fi

echo ""
echo "[3/8] Installing libinput for trackpad support..."
# Install libinput and xf86-input-libinput for trackpad support
sudo pacman -S --needed --noconfirm libinput xf86-input-libinput

echo ""
echo "[4/8] Installing wlroots-git (0.20) from AUR..."
# Arch official repos only have wlroots0.19 max, but MangoWC needs 0.20
# Install wlroots-git to provide libwlroots-0.20.so
yay -S --needed --noconfirm wlroots-git

echo ""
echo "[5/8] Installing scenefx-git..."
# MangoWC now requires scenefx-git specifically (not versioned scenefx0.4)
# scenefx-git provides libscenefx-0.4.so
yay -S --needed --noconfirm scenefx-git

echo ""
echo "[6/8] Installing MangoWC..."
# Install mangowc-git which uses scenefx-git
yay -S --needed --noconfirm mangowc-git

echo ""
echo "[7/8] Installing Noctalia Shell and its dependencies..."
# Install Noctalia and quickshell
yay -S --needed --noconfirm \
    noctalia-shell \
    quickshell \
    brightnessctl \
    imagemagick \
    python \
    ddcutil \
    cliphist \
    cava \
    wlsunset \
    xdg-desktop-portal \
    xdg-desktop-portal-wlr \
    evolution-data-server

echo ""
echo "[8/8] Installing essential desktop applications..."
# Terminal, launcher, notifications, clipboard, wallpaper, screenshots
yay -S --needed --noconfirm \
    foot \
    wmenu \
    wl-clipboard \
    grim \
    slurp \
    swaybg \
    mako \
    libnotify \
    polkit-gnome \
    bemenu \
    fuzzel \
    pipewire \
    wireplumber \
    ttf-jetbrains-mono-nerd \
    noto-fonts

echo ""
echo "=========================================="
echo "  Configuring MangoWC and Noctalia..."
echo "=========================================="

# Create config directories
mkdir -p ~/.config/mango
mkdir -p ~/.config/quickshell/noctalia-shell

# Copy default MangoWC config if it doesn't exist
if [ ! -f ~/.config/mango/config.conf ]; then
    if [ -f /etc/mango/config.conf ]; then
        cp /etc/mango/config.conf ~/.config/mango/
        echo "Copied default MangoWC config to ~/.config/mango/config.conf"
    else
        echo "Creating minimal MangoWC config..."
        cat > ~/.config/mango/config.conf << 'EOF'
# Minimal MangoWC Configuration
# See full documentation at: https://mangowc.vercel.app/docs/configuration

# Input configuration for trackpad
[input]
accel_profile=flat
accel_speed=0.0

# Trackpad specific settings
tap_to_click=1
natural_scrolling=1

# Autostart script
exec-once=~/.config/mango/autostart.sh

# Basic keybindings
bind=SUPER,Return,exec,foot
bind=SUPER,Q,kill
bind=SUPER,M,exit
bind=SUPER,Space,exec,wmenu-run

# Tags (workspaces)
bind=SUPER,1,view,1
bind=SUPER,2,view,2
bind=SUPER,3,view,3
bind=SUPER,4,view,4
bind=SUPER,5,view,5
EOF
    fi
fi

# Create MangoWC autostart script for Noctalia integration
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash

# Start PipeWire for audio
pipewire &
wireplumber &

# Notification daemon
mako &

# Policy kit authentication agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Clipboard history
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# Noctalia Shell (Quickshell)
# Noctalia uses quickshell which should auto-start
qs -c noctalia-shell &

# Set environment for screen sharing
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots

# Optional: Set wallpaper
# swaybg -i /path/to/wallpaper.jpg &
EOF

chmod +x ~/.config/mango/autostart.sh

# Ensure autostart is in config (if using default config)
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
echo "TRACKPAD CONFIGURATION:"
echo "------------------------"
echo "Trackpad is handled by libinput (installed and configured)."
echo "Settings are in: ~/.config/mango/config.conf"
echo ""
echo "Current settings applied:"
echo "  - accel_profile=flat (no mouse acceleration)"
echo "  - tap_to_click=1 (tap to click enabled)"
echo "  - natural_scrolling=1 (natural scrolling enabled)"
echo ""
echo "STARTING THE DESKTOP:"
echo "---------------------"
echo "1. From TTY, run: mango"
echo "2. Or add 'mango' to your display manager session if installed"
echo ""
echo "NOCTALIA SETUP:"
echo "---------------"
echo "Noctalia should start automatically with quickshell."
echo "First time users: A setup wizard may appear on first launch."
echo ""
echo "Useful keybindings (configured):"
echo "  Super+Enter = Terminal (foot)"
echo "  Super+Space = Launcher (wmenu)"
echo "  Super+Q     = Close window"
echo "  Super+M     = Exit MangoWC"
echo "  Super+1-5   = Switch to tag (workspace)"
echo ""
echo "TROUBLESHOOTING:"
echo "----------------"
echo "If Noctalia doesn't start automatically, run: qs -c noctalia-shell"
echo "If trackpad doesn't work, ensure xf86-input-libinput is installed"
echo "For screen sharing, ensure xdg-desktop-portal-wlr is running"
echo ""
