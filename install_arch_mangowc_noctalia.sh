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
echo "[1/6] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[2/6] Installing AUR helper (yay)..."
if ! command -v yay &> /dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay
else
    echo "yay already installed, skipping..."
fi

echo ""
echo "[3/6] Installing MangoWC and core Wayland dependencies..."
# MangoWC requires wlroots, scenefx, and various Wayland libraries
# Also installing essential tools for a functional desktop
yay -S --needed --noconfirm \
    mangowc-git \
    wlroots \
    scenefx \
    libinput \
    wayland \
    wayland-protocols \
    libdrm \
    libxkbcommon \
    pixman \
    libdisplay-info \
    libliftoff \
    hwdata \
    seatd \
    pcre2 \
    xorg-xwayland \
    libxcb

echo ""
echo "[4/6] Installing Noctalia Shell and its dependencies..."
# Noctalia requires Quickshell and various utilities
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
echo "[5/6] Installing essential desktop applications..."
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
    fuzzel

# Fonts
yay -S --needed --noconfirm ttf-jetbrains-mono-nerd noto-fonts

echo ""
echo "[6/6] Configuring MangoWC and Noctalia..."

# Create config directories
mkdir -p ~/.config/mango
mkdir -p ~/.config/quickshell/noctalia-shell

# Copy default MangoWC config if it doesn't exist
if [ ! -f ~/.config/mango/config.conf ]; then
    if [ -f /etc/mango/config.conf ]; then
        cp /etc/mango/config.conf ~/.config/mango/
        echo "Copied default MangoWC config to ~/.config/mango/config.conf"
    fi
fi

# Create MangoWC autostart script for Noctalia integration
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash

# Notification daemon
mako &

# Policy kit authentication agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Clipboard history
cliphist store &

# Noctalia Shell (starts automatically via quickshell, but ensure it's running)
# Noctalia uses quickshell which should auto-start when the compositor launches
# If not, you can add: qs -c noctalia-shell &

# Set environment for screen sharing
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
EOF

chmod +x ~/.config/mango/autostart.sh

# Add autostart to MangoWC config if not present
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
echo "MangoWC uses libinput for trackpad support."
echo "Trackpad settings are configured in: ~/.config/mango/config.conf"
echo ""
echo "Add these lines to your config for better trackpad support:"
echo ""
echo "  # Disable mouse acceleration (set to 1 for flat profile)"
echo "  accel_profile=1"
echo "  accel_speed=0.0"
echo ""
echo "  # Trackpad specific settings"
echo "  tracpad_natural_scrolling=1  # Enable natural scrolling"
echo "  tap_to_click=1               # Enable tap to click"
echo ""
echo "STARTING THE DESKTOP:"
echo "---------------------"
echo "1. From TTY, run: mango"
echo "2. Or add 'mango' to your display manager session if installed"
echo ""
echo "NOCTALIA SETUP:"
echo "---------------"
echo "Noctalia should start automatically with quickshell."
echo "Run 'qs' to start quickshell manually if needed."
echo ""
echo "First time Noctalia users: A setup wizard will appear on first launch."
echo ""
echo "Useful keybindings (default MangoWC):"
echo "  Super+Enter = Terminal (foot)"
echo "  Super+Space = Launcher (check your config)"
echo "  Super+Shift+Q = Quit"
echo ""
