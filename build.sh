#!/bin/bash
umask 022
set -ex
if [[ ! -d build ]] ; then
    rm -rf build
fi
# fetch & extract rootfs
mkdir -p build
cd build
uri="https://dl-cdn.alpinelinux.org/alpine/edge/releases/$(uname -m)/"
tarball=$(wget -O - "$uri" |grep "alpine-minirootfs" | grep "tar.gz<" | \
    sort -V | tail -n 1 | cut -f2 -d"\"")
wget -O "$tarball" "$uri/$tarball"
mkdir -p chroot
cd chroot
tar -xvf ../*$tarball
# fix resolv.conf
install /etc/resolv.conf ./etc/resolv.conf
# add repositories
cat > ./etc/apk/repositories <<EOF
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
https://dl-cdn.alpinelinux.org/alpine/edge/testing
https://dl-cdn.alpinelinux.org/alpine/latest-stable/main
https://dl-cdn.alpinelinux.org/alpine/latest-stable/community
EOF
# upgrade if needed
chroot ./ apk upgrade
chroot ./ apk add os-prober grub grub-bios grub-efi bash lsblk efibootmgr || true
chroot ./ apk add linux-edge linux-firmware-none || true
chroot ./ apk add eudev || true
chroot ./ apk add depmod -a || true
cat > ./init << EOF
#!/bin/bash
clear
mount -t sysfs sysfs /sys
mount -t proc proc /proc
/sbin/udevd &
udevadm trigger -c add
udevadm settle
mdev -s
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
modprobe ext4
modprobe vfat
modprobe efivars
mount -t efivarfs efivarfs /sys/firmware/efi/efivars
mount /dev/\$rootfs /mnt
grub-install --bootloader-id=grub --boot-directory=/mnt/boot --efi-directory=/mnt --root-directory=/mnt --locales= --removable --force --compress=gz /dev/\$mbr
efibootmgr --create --disk /dev/\$mbr --part \${rootfs/*[a-z]/} --loader /EFI/BOOT/grubx64.efi --label "grub"
export pkgdatadir=/usr/share/grub/
mkdir -p /var/lib/os-prober
echo "terminal_output console" > /mnt/boot/grub/grub.cfg
bash /etc/grub.d/00_header >> /mnt/boot/grub/grub.cfg
bash /etc/grub.d/30_os-prober >> /mnt/boot/grub/grub.cfg
echo "menuentry exit {" >> /mnt/boot/grub/grub.cfg
echo "    exit {" >> /mnt/boot/grub/grub.cfg
echo "}" >> /mnt/boot/grub/grub.cfg
sync ; echo b > /proc/sysrq-trigger
EOF
chmod +x ./init

mv boot/vmlinuz-edge ../
rm -rf ./lib/modules/*/kernel/drivers/gpu
rm -rf ./lib/modules/*/kernel/drivers/media
rm -rf ./lib/modules/*/kernel/drivers/net
rm -rf ./lib/modules/*/kernel/sound/
rm -rf ./lib/modules/*/kernel/net/
rm -rf boot var
find . | cpio -H newc -o > ../initrd-edge
cd ..
mkdir -p iso/boot/grub
cp initrd-edge iso/initrd
gzip -9 iso/initrd
cp vmlinuz-edge iso/linux
cat > iso/boot/grub/grub.cfg << EOF
insmod all_video
terminal_output console
terminal_input console
linux /linux init=/init boot=live quiet
initrd /initrd.gz
boot
EOF
grub-mkrescue iso -o ../grub-os-$(date +%s).iso
