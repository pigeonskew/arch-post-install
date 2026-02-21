#!/bin/bash
# Arch Linux System Preparation Script
# Prepares hardware, software compatibility, and login auto-start
# Note: WM (MangoWC) and Shell (Noctalia) must be installed manually

set -e  # Exit on error

echo "=========================================="
echo "  Arch System Preparation Script"
echo "  (Hardware & Compatibility Focus)"
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
echo "[1/6] Enabling necessary repositories (multilib)..."
# Enable multilib repo for broader software compatibility (Steam, proprietary apps)
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "Enabling [multilib] repository..."
    sudo sed -i '/^\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
else
    echo "[multilib] repository already enabled."
fi

echo ""
echo "[2/6] Updating system and installing base dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

echo ""
echo "[3/6] Installing AUR helper (yay)..."
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
echo "[4/6] Installing Hardware Compatibility Packages..."
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
echo "[5/6] Installing Desktop Utilities & Fonts..."
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
echo "[6/6] Configuring Auto-start on Login..."
# Add MangoWC autostart to .bash_profile if not already present
# This ensures Mango starts automatically when you log in on tty1
# NOTE: Ensure you install MangoWC manually before logging in, or this will fail.
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

# Generate XDG directories
xdg-user-dirs-update

echo ""
echo "=========================================="
echo "  System Preparation Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Please install MangoWC and Noctalia Shell manually."
echo "Example:"
echo "  yay -S mangowc-git"
echo "  yay -S noctalia-shell"
echo ""
echo "IMPORTANT: Please reboot your system after installing the WM."
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
echo "Note: No configuration files were generated for MangoWC/Noctalia."
echo "Please configure them manually after installation."
echo ""
