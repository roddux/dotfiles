# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls -lAhF --color=auto'
alias l=ls
alias vim=nvim
PS1='[\u@\h \W]\$ '

export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
export PATH="$PATH:/home/user/go/bin/"

export GOPATH="$HOME/go"

if [ -e /home/user/.nix-profile/etc/profile.d/nix.sh ]; then . /home/user/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

alias go15shell='docker run --hostname=golang1-15-8 --rm --interactive=true --tty=true --workdir=/code -v$(pwd):/code golang:1.15.8 /bin/bash'

if [ "$DISPLAY" == "" ]; then
	echo "Starting X";
	startx;
fi
