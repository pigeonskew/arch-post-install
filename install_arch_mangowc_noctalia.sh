#!/bin/bash

# Exit on error
set -e

echo "--- Starting MangoWC + Noctalia Installation ---"

# 1. Update system and install base dependencies
echo "Updating system and installing base-devel/git..."
sudo pacman -Syu --needed base-devel git libinput xf86-input-libinput mesa

# 2. Install 'yay' as an AUR helper if not present
if ! command -v yay &> /dev/null; then
    echo "Installing yay (AUR helper)..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
fi

# 3. Enable Trackpad (Tap-to-click & Natural Scrolling)
echo "Configuring trackpad..."
sudo mkdir -p /etc/X11/xorg.conf.d/
sudo tee /etc/X11/xorg.conf.d/30-touchpad.conf > /dev/null <<EOF
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
    Option "ClickMethod" "clickfinger"
EndSection
EOF

# 4. Install MangoWC and Noctalia Shell
# mangowc-git provides the compositor
# noctalia-shell provides the UI elements
echo "Installing MangoWC and Noctalia Shell from AUR..."
yay -S --noconfirm mangowc-git noctalia-shell-git

# 5. Install basic necessities for a Wayland environment
# foot: recommended terminal for MangoWC
# wmenu: for app launching
echo "Installing environment essentials (foot, wmenu, brightnessctl)..."
sudo pacman -S --needed foot wmenu brightnessctl wl-clipboard

echo "--- Installation Complete ---"
echo "You can now start MangoWC by typing: mangowc"
echo "Note: You may need to configure noctalia-shell to autostart in ~/.config/mango/config.conf"
