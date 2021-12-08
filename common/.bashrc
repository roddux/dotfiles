# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls -lAhF --color=auto'
alias l=ls
alias vi=nvim
alias vim=nvim
alias fd="fd -HI" # find all the filez
alias rg="rg -uu --hidden" # read from all the filez
PS1='[\u@\h \W]\$ '
alias cls="printf '\ec'" # faster than 'reset'
alias cat=bat # mostly for pretty markdown output tbh

export PATH="$PATH:$HOME/go/bin/" # golang
# export PATH="$PATH:$HOME/go/bin/" # cargo 
export PATH="$PATH:$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin" # node

export EDITOR=nvim
export GOPATH="$HOME/go"
export GDK_SCALE=2 # everything is hidpi now...

alias go15shell='docker run --hostname=golang1-15-8 --rm --interactive=true --tty=true --workdir=/code -v$(pwd):/code golang:1.15.8 /bin/bash'

alias fuck='sudo $(history -p !!)'

if [ "$DISPLAY" == "" ] && [ ! -f /tmp/.X*-lock ]; then
	echo "Starting X";
	startx;
fi

unhex() {
	python3 -c "from sys import argv; print([int(y) for y in bytes.fromhex(argv[1])])" $1
}
