install qemu
```
sudo apt install qemu-utils qemu-system-x86 qemu-system-gui
mkdir sources
```
mount system to /mnt/gentoo \
then move stuff to approriate locations to build a new kernel
```
cp -r /mnt/gentoo/usr/src/linux-*  ~/sources
sudo mv /lib/firmware /lib/firmware.bak && rmdir /lib/firmware
sudo ln -s /mnt/gentoo/lib/firmware /lib/firmware
```
make initramfs stuff
```
cd ~/sources
mkdir initramfs
sudo ln -s "$PWD/initramfs" /usr/src/initramfs
```
