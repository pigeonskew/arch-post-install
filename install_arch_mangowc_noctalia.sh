#!/bin/bash
# MangoWC + Noctalia Shell Installation Script for Arch Linux (FIXED)
# Run this after base Arch installation (no DE/shell)

set -e  # Exit on error

echo "=========================================="
echo "  MangoWC + Noctalia Shell Installer"
echo "  (Fixed for wlroots dependency issues)"
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
echo "[3/7] Installing official wlroots first (avoiding broken -git version)..."
# Install official wlroots from repos to satisfy dependencies
# This prevents yay from trying to build wlroots-asan-git which is broken
sudo pacman -S --needed --noconfirm wlroots libinput xf86-input-libinput

echo ""
echo "[4/7] Installing scenefx (required by mangowc-git)..."
# Install scenefx from AUR (needed for mangowc-git, not wlonly version)
yay -S --needed --noconfirm scenefx

echo ""
echo "[5/7] Installing MangoWC (using scenefx version to avoid wlroots-git)..."
# Use mangowc-git which depends on scenefx + official wlroots
# instead of mangowc-wlonly-git which requires wlroots-git (broken)
yay -S --needed --noconfirm mangowc-git

echo ""
echo "[6/7] Installing Noctalia Shell and its dependencies..."
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
echo "[7/7] Installing essential desktop applications..."
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
echo "TOUCHPAD CONFIGURATION:"
echo "------------------------"
echo "Trackpad settings are configured in: ~/.config/mango/config.conf"
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
