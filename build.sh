#!/bin/bash
set -e
#### Check root
if [[ ! $UID -eq 0 ]] ; then
    echo -e "\033[31;1mYou must be root!\033[:0m"
    exit 1
fi
#### Remove all environmental variable
for e in $(env | sed "s/=.*//g") ; do
    unset "$e" &>/dev/null
done

#### Set environmental variables
export PATH=/bin:/usr/bin:/sbin:/usr/sbin
export LANG=C
export SHELL=/bin/bash
export TERM=linux
export DEBIAN_FRONTEND=noninteractive

#### Install dependencies
if which apt &>/dev/null && [[ -d /var/lib/dpkg && -d /etc/apt ]] ; then
    apt-get update
    apt-get install curl mtools squashfs-tools grub-pc-bin grub-efi xorriso debootstrap -y
fi
set -ex
rm -rf grub-os isowork grub-os-install.iso || true
debootstrap --variant=minbase --arch=amd64 --no-check-gpg --no-merged-usr sid grub-os
chroot grub-os apt install grub-pc-bin grub-efi grub-common os-prober ntfs-3g efibootmgr zstd -y
chroot grub-os apt install linux-image-amd64 --no-install-recommends live-boot -y
rm -rf grub-os/lib/modules/*/kernel/drivers/gpu
rm -rf grub-os/lib/modules/*/kernel/drivers/media
rm -rf grub-os/lib/modules/*/kernel/drivers/net
rm -rf grub-os/lib/modules/*/kernel/sound/
rm -rf grub-os/lib/modules/*/kernel/net/
chroot grub-os update-initramfs -u -k all
cat > grub-os/init << EOF
#!/bin/bash
clear
/lib/systemd/systemd-udevd &
udevadm trigger
udevadm settle
clear
while [[ ! -b /dev/\$rootfs ]] ; do
    lsblk
    echo "Input rootfs/efi directory"
    read rootfs
done
clear
while [[ ! -b /dev/\$mbr ]] ; do
    lsblk
    echo "Input mbr"
    read mbr
done
clear
modprobe efivars
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
mount /dev/\$rootfs /mnt
grub-install --bootloader-id=grub --boot-directory=/mnt/boot --efi-directory=/mnt --root-directory=/mnt --locales= --removable --force --compress=gz /dev/\$mbr
efibootmgr --create --disk /dev/\$mbr --part \${rootfs/*[a-z]/} --loader /EFI/BOOT/grubx64.efi --label "grub"
export pkgdatadir=/usr/lib/grub
mkdir -p /var/lib/os-prober
bash /etc/grub.d/00_header > /mnt/boot/grub/grub.cfg
bash /etc/grub.d/30_os-prober >> /mnt/boot/grub/grub.cfg
echo "menuentry exit {" >> /mnt/boot/grub/grub.cfg
echo "    exit {" >> /mnt/boot/grub/grub.cfg
echo "}" >> /mnt/boot/grub/grub.cfg
sync ; echo b > /proc/sysrq-trigger
EOF
chmod +x grub-os/init
chroot grub-os apt clean
mkdir -p isowork/live isowork/boot/grub/
cat grub-os/vmlinuz > isowork/linux
cat grub-os/initrd.img > isowork/initrd
cat > isowork/boot/grub/grub.cfg << EOF
insmod all_video
terminal_output console
terminal_input console
linux /linux init=/init boot=live quiet
initrd /initrd
boot
EOF
rm -rf grub-os/var grub-os/usr/share/locale/* grub-os/usr/share/man grub-os/boot grub-os/usr/share/help
find grub-os/usr/lib/grub | grep gfx | xargs rm -fv
mksquashfs grub-os isowork/live/filesystem.squashfs -comp xz -wildcards

#### Create iso
grub-mkrescue isowork -o grub-os-$(date +%s).iso
