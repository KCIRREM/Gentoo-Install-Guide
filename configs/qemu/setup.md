clone this repo
```
https://github.com/KCIRREM/Gentoo-Install-Guide.git
cd Gentoo-Install-Guide/configs/scripts
```
edit the remount.sh in the scripts forlder with your luks password
```
chmod +x {remount.sh,initramfs_gen.sh}
mkdir ~/sources
cp initramfs_gen.sh ~/sources/
sudo ./remount.sh
```
install qemu and kernel tools
```
sudo apt install qemu-utils qemu-system-x86 qemu-system-gui build-essential libncurses-dev bison flex libssl-dev libelf-dev
mkdir ~/sources
```
move stuff to approriate locations to build a new kernel
```
cp -r /mnt/gentoo/usr/src/linux-*  ~/sources/
sudo mv /lib/firmware /lib/firmware.bak && rmdir /lib/firmware
sudo ln -s /mnt/gentoo/lib/firmware /lib/firmware
```
make initramfs stuff
```
mkdir ~/sources/initramfs && cd ~/sources
sudo ln -s "$PWD/initramfs" /usr/src/initramfs
```
create a basic initramfs && init file within the initramfs directory \
(initramfs_list)
```
# directory structure
dir /proc       754 0 0
dir /bin        755 0 0
dir /sbin       755 0 0
dir /mnt        755 0 0
dir /mnt/root   755 0 0
dir /root       700 0 0
dir /dev        755 0 0
dir /sys	755 0 0
dir /run	755 0 0

#init
file /init /usr/src/initramfs/init 755 0 0

# busybox
file /bin/busybox /bin/busybox 755 0 0

# devices
nod /dev/null   666 0 0 c 1 3
nod /dev/tty    666 0 0 c 5 0
nod /dev/console        600 0 0 c 5 1
```
(init)
```
#!/bin/busybox sh

rescue_shell() {
    echo "$@"
    echo "Something went wrong. Dropping you to a shell."
    # The symlinks are not required any longer
    # but it helps tab completion
    /bin/busybox --install -s
    exec /bin/sh
}


busybox mount -t devtmpfs none /dev || rescue_shell "Error: mount /devtmpfs failed !"
busybox mount -t proc none /proc || rescue_shell "Error: mount /proc failed !"
busybox mount -t sysfs none /sys || rescue_shell "Error: mount /sysfs failed !"
busybox mount -t ext4 /dev/sda1 /root || rescule_shell "Error root mount failed"
echo "All done. Switching to real root."

umount /proc
umount /sys
mount -o move /dev /mnt/root/dev

exec switch_root /mnt/root /sbin/init
```
generate initramfs
```
cd ~/sources/linux-*/
sh ../initramfs_gen.sh $PWD
```
run qemu
```
qemu-system-x86_64 -kernel ~/sources/linux-*/arch/x86_64/boot/bzImage -initrd ~sources/initramfs/initramfs.cpio.gz -serial stdio -append "root=/dev/ram0 console=ttyAMA0 console=ttyS0"
```
