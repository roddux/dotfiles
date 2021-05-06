#!/bin/sh
set -Eeuo pipefail

set -x
# This script has 3 stages. The same script runs on the host, in the
# pre-install environment within the VM and in the chroot-install environment
# in the VM. The first argument to this script controls which stage executes.

# These can be overridden by setting an environment variable of the same name
CACHE_FILEPATH="${CACHE_FILEPATH:=~/.package_cache.tar}"
CACHE_FILE=$(basename $CACHE_FILEPATH)
# Cache downloaded packages in the guest onto the host (yes/no) [yes]
USE_CACHE="${USE_CACHE:=yes}"
# Collect package cache from VM and update host package cache (yes/no) [yes]
NEW_CACHE="${NEW_CACHE:=yes}"
# Set a new pacman mirrorlist (yes/no) [no]
NEW_MIRRORLIST="${NEW_MIRRORLIST:=no}"

VM="${VM=$(date +%d%b%y)}" # Default to ddMonthyy
SCRIPT_NAME=$0

run_host() {
# Config information
cat <<E
CACHE_FILEPATH: $CACHE_FILEPATH
    CACHE_FILE: $CACHE_FILE
     USE_CACHE: $USE_CACHE
     NEW_CACHE: $NEW_CACHE
NEW_MIRRORLIST: $NEW_MIRRORLIST
   SCRIPT PATH: $0
            VM: $VM
E

# Instruct user
cat <<E
#1: Boot your VM in UEFI mode and get into the Arch pre-install environment.
#2: Set yourself a root password and make sure SSH is open to connections.

Hit enter once ready. 
E

read

echo -n "Okay, now type your VM IP address: "
read VMIP

umask 077 # don't want anyone reading the keys
TMPKEY=$(mktemp tmp-ssh-key-XXXXXX) # generate a name
rm $TMPKEY # ssh-keygen will overwrite it anyway

echo "Generating temporary SSH key"
ssh-keygen -N "" -t ecdsa -f $TMPKEY

echo "Got ssh key: $TMPKEY"
cat $TMPKEY

echo "Copying temporary SSH key to VM"
cat $TMPKEY.pub | ssh -o 'StrictHostKeyChecking accept-new' root@$VMIP -- "rm -rf /root/.ssh; mkdir /root/.ssh; cat >/root/.ssh/authorized_keys </dev/stdin"

echo "Copying install script to VM"
scp -i $TMPKEY $SCRIPT_NAME root@$VMIP:/

if [ "$USE_CACHE" == "yes" ]; then
	echo "Checking for local package cache"
	if [ -f "$CACHE_FILEPATH" ]; then
		echo "Loading host package cache onto VM"
		scp -i $TMPKEY $CACHE_FILEPATH root@$VMIP:/tmp/
	else
		echo "No local package cache available"
	fi
fi

echo "Running install script in VM"
ssh -i $TMPKEY root@$VMIP -- NEW_MIRRORLIST=$NEW_MIRRORLIST USE_CACHE=$USE_CACHE CACHE_FILE=$CACHE_FILE NEW_CACHE=$NEW_CACHE /$SCRIPT_NAME preinstall

if [ "$NEW_CACHE" == "yes" ]; then # download new package cache from vm
	echo "Retrieving new package cache"
	scp -i $TMPKEY root@$VMIP:/mnt/var/cache/pacman/$CACHE_FILE $CACHE_FILEPATH
	echo "Rebooting VM" # if NEW_CACHE is no, VM reboots itself
	ssh -i $TMPKEY root@$VMIP -- "reboot"
fi

echo "Removing temporary SSH keys from host"
rm -f $TMPKEY $TMPKEY.pub
}

run_preinstall() {
echo "=> Now in preinstall"
echo "Setting up NTP"
timedatectl set-ntp true

echo "Unmounting disks (cleaning up, if re-running)"
umount -R /mnt || true

echo "Partitioning disk"
echo -e ",100m\n;\n" | sfdisk -X gpt /dev/sda

echo "Waiting for kernel to recognise partition changes"
while ! test -b /dev/sda1; do sleep 0.1; done

echo "Formatting disk"
mkfs.fat -F32 /dev/sda1 # /boot BIOS partition
mkfs.xfs -f /dev/sda2   # /root XFS partition

echo "Mounting partitions"
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

if [ "$NEW_MIRRORLIST" == "yes" ]; then
	echo "Updating mirror list"
	reflector --latest 20 --sort rate --country "United Kingdom" --save /etc/pacman.d/mirrorlist
else
	echo "Setting mirror list"
	cat <<E > /etc/pacman.d/mirrorlist
Server = http://mirrors.manchester.m247.com/arch-linux/\$repo/os/\$arch
Server = http://lon.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://lon.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://mirror.bytemark.co.uk/archlinux/\$repo/os/\$arch
Server = http://mirror.bytemark.co.uk/archlinux/\$repo/os/\$arch
Server = rsync://lon.mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = rsync://mirror.bytemark.co.uk/archlinux/\$repo/os/\$arch
Server = rsync://mirrors.manchester.m247.com/archlinux/\$repo/os/\$arch
Server = http://www.mirrorservice.org/sites/ftp.archlinux.org/\$repo/os/\$arch
Server = rsync://rsync.mirrorservice.org/ftp.archlinux.org/\$repo/os/\$arch
Server = https://mirror.netweaver.uk/archlinux/\$repo/os/\$arch
Server = https://www.mirrorservice.org/sites/ftp.archlinux.org/\$repo/os/\$arch
Server = http://archlinux.mirrors.uk2.net/\$repo/os/\$arch
Server = https://archlinux.uk.mirror.allworldit.com/archlinux/\$repo/os/\$arch
Server = rsync://mirrors.uk2.net/archlinux/\$repo/os/\$arch
Server = http://mirror.netweaver.uk/archlinux/\$repo/os/\$arch
Server = http://mirrors.ukfast.co.uk/sites/archlinux.org/\$repo/os/\$arch
Server = rsync://archlinux.uk.mirror.allworldit.com/archlinux/\$repo/os/\$arch
Server = https://mirrors.ukfast.co.uk/sites/archlinux.org/\$repo/os/\$arch
Server = http://archlinux.uk.mirror.allworldit.com/archlinux/\$repo/os/\$arch
E
fi

if [ "$USE_CACHE" == "yes" ]; then
	if [ -f "/tmp/$CACHE_FILE" ]; then
		echo "Found package cache"
		mkdir -p /mnt/var/cache/pacman || true
		mv /tmp/$CACHE_FILE /mnt/var/cache/pacman
		pushd /mnt/var/cache/pacman
		echo "Extracting package cache"
		tar xf ./$CACHE_FILE
		popd
	else
		echo "Told to use cache, but no cache file present!"
		exit 1
	fi
fi

echo "Installing base packages"
pacstrap /mnt \
	base \
	base-devel \
	bind \
	linux-lts \
	linux-firmware \
	neovim \
	man-db \
	man-pages \
	grub \
	efibootmgr \
	xfsprogs \
	dhcpcd \
	mesa \
	xorg-server \
	xorg-server-common \
	xf86-video-vmware \
	xorg-xinit \
	xorg-xrandr \
	xorg-xrdb \
	rxvt-unicode \
	firefox \
	chromium \
	xterm \
	i3-gaps \
	i3status \
	rofi \
	python \
	go \
	git \
	dmenu

echo "Generating fstab"
genfstab -U /mnt > /mnt/etc/fstab

echo "Copying install script to chroot" 
cp $SCRIPT_NAME /mnt/

echo "Entering chroot"
arch-chroot /mnt /$SCRIPT_NAME chroot

echo "=> Back in preinstall" 
echo "Synchronising filesystem changes" 
sync

if [ "$NEW_CACHE" == "yes" ]; then
	echo "Building new package cache"
	pushd /mnt/var/cache/pacman/
	tar cf $CACHE_FILE ./pkg/
else
	echo "Rebooting"
	reboot
fi
}

run_chroot() {
echo "=> Now in chroot"
echo "Setting timezone"
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
hwclock --systohc
timedatectl set-ntp true

echo "Setting locale"
cat <<E > /etc/locale.gen
en_GB.UTF-8 UTF-8
E

locale-gen

cat <<E > /etc/locale.conf
LANG=en_GB.UTF-8
E

echo "Setting hostname"
echo $VM > /etc/hostname
hostnamectl set-hostname $VM

echo "Setting up hosts file"
cat <<E > /etc/hosts
127.0.0.1	localhost
::1		localhost
127.0.0.1	$VM.localdomain $VM
E

echo "Installing bootloader"
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=arch-grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "Adding user 'user'"
useradd -m user

echo "Setting passwords"
echo 'user:user' | chpasswd
echo 'root:root' | chpasswd

# TODO: open-vm-tools service, firefox/chrome ublock addin

# Setup dotfiles
echo "Downloading dotfiles"
pushd /tmp
git clone https://github.com/roddux/dotfiles.git
pushd dotfiles/vmware
echo "Copying vmware dotfiles"
cp -r ./.* ./* /home/user/
popd; pushd dotfiles/common
echo "Copying common dotfiles"
cp -r ./.* ./* /home/user/
popd
}

if [ $# -eq 0 ]; then
	MODE="host"
elif [ $# -eq 1 ]; then
	MODE="$1"
fi

if [ "$MODE" == "host" ]; then
	run_host
elif [ "$MODE" == "preinstall" ]; then
	run_preinstall
elif [ "$MODE" == "chroot" ]; then
	run_chroot
else
	echo "Invalid argument"
	exit 1
fi
