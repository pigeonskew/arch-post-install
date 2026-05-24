#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

export EDITOR=vim

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias music='shellbeats'
alias anime='ani-cli'
alias nv='nvim'
PS1='[\u@\h \W]\$ '

clean() {
    sudo find /var/cache/pacman/pkg/ -name "download-*" -delete 2>/dev/null
    sudo pacman -Sc --noconfirm
    
    if pacman -Qdtq &>/dev/null; then
        sudo pacman -Rs $(pacman -Qdtq) --noconfirm
    else
        echo "No orphaned packages to remove."
    fi
    
    sudo paccache -rk3
    sudo journalctl --vacuum-size=100M
    rm -rf ~/.cache/* ~/.local/share/Trash/*
}

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec mango
fi

export QT_QPA_PLATFORM=wayland
fastfetch
export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/share:/usr/local/share}"
