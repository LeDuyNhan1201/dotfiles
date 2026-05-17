set -g fish_greeting

set -x GTK_IM_MODULE fcitx
set -x QT_IM_MODULE fcitx
set -x XMODIFIERS @im=fcitx

if test (tty) = /dev/tty1
    exec startx
end

if status is-interactive
   starship init fish | source
end
alias dotfiles='git --git-dir=/home/ben/.dotfiles --work-tree=/home/ben'
