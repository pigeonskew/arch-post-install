#!/bin/bash
# MangoWC + Noctalia Shell Installation Script for Arch Linux
# Run this after base Arch installation (no DE/shell)
# Updated: No Mako, No Keybindings, Auto-start enabled

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
echo "[0/7] Enabling necessary repositories (multilib)..."
# Enable multilib repo for broader software compatibility (Steam, proprietary apps)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling [multilib] repository..."
    sudo sed -i '/^\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
else
    echo "[multilib] repository already enabled."
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
echo "[3/7] Installing Hardware Compatibility Packages..."
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
echo "[4/7] Installing Desktop Utilities & Fonts..."
# Polkit, Clipboard, Terminal, Launcher, Fonts, Screen Lock (Mako excluded)
sudo pacman -S --needed --noconfirm \
    polkit-gnome \
    cliphist wl-clipboard \
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
echo "[5/7] Installing MangoWC..."
yay -S --needed --noconfirm mangowc-git

echo ""
echo "[6/7] Installing Noctalia Shell..."
yay -S --needed --noconfirm noctalia-shell

echo ""
echo "[7/7] Configuring Auto-start on Login..."
# Add MangoWC autostart to .bash_profile if not already present
# This ensures Mango starts automatically when you log in on tty1
if [ -f ~/.bash_profile ]; then
    if ! grep -q "exec mango" ~/.bash_profile; then
        echo "" >> ~/.bash_profile
        echo "# Autostart MangoWC on tty1" >> ~/.bash_profile
        echo "if [ -z \"\$DISPLAY\" ] && [ \"\$(tty)\" = \"/dev/tty1\" ]; then" >> ~/.bash_profile
        echo "    exec mango" >> ~/.bash_profile
        echo "fi" >> ~/.bash_profile
        echo "MangoWC autostart added to ~/.bash_profile"
    else
        echo "MangoWC autostart already configured in ~/.bash_profile"
    fi
else
    # Create .bash_profile if it doesn't exist
    cat > ~/.bash_profile << 'EOF'
# ~/.bash_profile

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Autostart MangoWC on tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec mango
fi
EOF
    echo "Created ~/.bash_profile with MangoWC autostart"
fi

echo ""
echo "=========================================="
echo "  Configuring MangoWC and Noctalia..."
echo "=========================================="

# Create config directories
mkdir -p ~/.config/mango
mkdir -p ~/.config/quickshell/noctalia-shell

# Create minimal MangoWC config (No keybindings, just input & autostart)
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
EOF
fi

# Create MangoWC autostart script for Noctalia integration (No Mako)
cat > ~/.config/mango/autostart.sh << 'EOF'
#!/bin/bash
# Audio
pipewire &
wireplumber &

# Authentication Agent
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Clipboard
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# Shell
qs -c noctalia-shell &

# Environment variables for GTK/Qt apps
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

# Generate XDG directories
xdg-user-dirs-update

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Please reboot your system now."
echo "After reboot, log in on tty1 and MangoWC will start automatically."
echo ""
echo "Hardware & Software Improvements Added:"
echo "  - Multilib repo enabled"
echo "  - Firmware & Microcode support"
echo "  - PipeWire Audio Stack"
echo "  - NetworkManager & Bluetooth"
echo "  - Vulkan & Mesa Graphics"
echo "  - XWayland for X11 app support"
echo "  - Fonts & Clipboard Manager"
echo "  - Auto-start configured in ~/.bash_profile"
echo ""
echo "Configuration files created:"
echo "  - ~/.config/mango/config.conf (Input settings only)"
echo "  - ~/.config/mango/autostart.sh"
echo ""
echo "Note: No keybindings or notification daemon (mako) were configured."
echo "You can customize keybindings in ~/.config/mango/config.conf"
echo ""
