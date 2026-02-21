#!/bin/bash

# Exit on error
set -e

echo "--- Advanced MangoWC + Noctalia Setup ---"

# 1. Core Dependencies & VM Graphics Drivers
# Including mesa-utils and guest tools for better VM compatibility
sudo pacman -Syu --needed base-devel git libinput mesa mesa-utils xdg-desktop-portal-wlr xdg-desktop-portal-gtk seatd foot wmenu

# 2. Permissions (Crucial for Wayland/Trackpads)
echo "Setting up seatd and user permissions..."
sudo systemctl enable --now seatd
sudo gpasswd -a $USER seat
# Note: You may need to reboot after the script for group changes to take effect.

# 3. Install 'yay' AUR Helper
if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    cd /tmp && git clone https://aur.archlinux.org/yay.git
    cd yay && makepkg -si --noconfirm
    cd ~
fi

# 4. Install the Compositor and Shell
echo "Building MangoWC and Noctalia from AUR..."
yay -S --noconfirm mangowc-git noctalia-shell-git

# 5. Trackpad Configuration (System-wide)
echo "Configuring trackpad..."
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null <<EOF
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
EndSection
EOF

# 6. MangoWC Configuration & Noctalia Autostart
echo "Initializing MangoWC config..."
mkdir -p ~/.config/mango
# If the system default exists, copy it; otherwise, create a basic starter
if [ -f /etc/mango/config.conf ]; then
    cp /etc/mango/config.conf ~/.config/mango/config.conf
else
    # Fallback: Create a minimal config if the package didn't provide one
    cat <<EOF > ~/.config/mango/config.conf
# MangoWC Minimal Config
modifier=Mod4
terminal=foot
launcher=wmenu_run
# Autostart Noctalia Shell
exec-once=noctalia-shell
EOF
fi

# Append Noctalia to the config if it's not already there
grep -q "noctalia-shell" ~/.config/mango/config.conf || echo "exec-once=noctalia-shell" >> ~/.config/mango/config.conf

echo "--- Setup Finished ---"
echo "IMPORTANT: Please REBOOT your machine now."
echo "After rebooting, log in and type: mango"
