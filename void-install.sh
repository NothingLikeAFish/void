#!/bin/sh

set -eu

DRIVE=/dev/nvme0n1
HOSTNAME=thinkpad
USERNAME=jasper
REPO=https://repo-default.voidlinux.org/current
ARCH=x86_64-musl

# Packages needed for installation
xbps-install -S parted xtools
# Drive setup
wipefs -a "$DRIVE"
parted -s "$DRIVE" \
    mklabel gpt \
    mkpart EFI fat32 1MiB 1GiB \
    set 1 esp on \
    mkpart ROOT btrfs 1GiB 100%
# Format partitions
mkfs.fat -F32 "${DRIVE}p1"
mkfs.btrfs "${DRIVE}p2"
# Mount EFI partition
mkdir -p /mnt/boot/efi
mount "${DRIVE}p1" /mnt/boot/efi
# Mount and make btrfs subvolumes
mkdir -p /mnt
mount "${DRIVE}p2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
umount /mnt
mount -o subvol=@,compress=zstd "${DRIVE}p2" /mnt
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd "${DRIVE}p2" /mnt/home
# Copy XBPS keys
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
# Install base system
XBPS_ARCH="$ARCH" xbps-install -S -r /mnt -R "$REPO" base-system
# Generate fstab
xgenfstab -U /mnt > /mnt/etc/fstab
# Chroot into the new system
xchroot /mnt /bin/bash
# Install packages
xbps-install -S \
    grub-x86_64-efi \
    NetworkManager \
    dbus
# Configure system
echo "$HOSTNAME" > /etc/hostname
echo "KEYMAP=us" > /etc/rc.conf
# Wifi services
ln -s /etc/sv/dbus /var/service/
ln -s /etc/sv/NetworkManager /var/service/
rm -f /var/service/dhcpcd
rm -f /var/service/wpa_supplicant
# Disable root login
passwd -l root
# Make user
useradd -m -G wheel,network,audio,video,input,storage,kvm -s /bin/bash "$USERNAME"
passwd "$USERNAME"
# Configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="VOID"
# Final
xbps-reconfigure -fa
umount -R /mnt
echo "Done!"
