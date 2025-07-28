# Gentoo-Install-Guide
## An encrypted Gentoo install with btrfs and subvolumes along withe efistub as the bootloader.

500M, 19GB, rest is root \
efi partiton, swap, luks on btrfs 

format appropriately 
setup passphrase 
```
cryptsetup luksFormat --key-size 512 /dev/nvme0n1p3 
cryptsetup luksOpen /dev/nvme0n1p3 cryptroot 
mkfs.btrfs /dev/mapper/cryptroot 
mkdir -p /mnt/gentoo 
mount /dev/mapper/cryptroot /mnt/gentoo 
cd /mnt/gentoo 
```
create subvols 
```
btrfs subvol create {@,@home,@tmp,@cache,@repos,@log,@binpkgs,@snapshots} 
```
mount 
```
cd ../ 
umount /mnt/gentoo 
mount -o defaults,noatime,compress-force=zstd,subvol=@ /dev/mapper/cryptroot /mnt/gentoo/ 
cd /mnt/gentoo 
mkdir ./{home,.snapshots,var,efi} 
mkdir ./var/{cache,db,log,tmp} 
mkdir ./var/db/repos 
mount /dev/nvme0n1p1 /mnt/gentoo/efi 
mount -o defaults,noatime,compress-force=zstd,subvol=@home /dev/mapper/cryptroot /mnt/gentoo/home 
mount -o defaults,noatime,compress-force=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/gentoo/.snapshots 
mount -o defaults,noatime,compress-force=zstd,subvol=@tmp /dev/mapper/cryptroot /mnt/gentoo/var/tmp 
mount -o defaults,noatime,compress-force=zstd,subvol=@log /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o defaults,noatime,compress-force=zstd,subvol=@cache /dev/mapper/cryptroot /mnt/gentoo/var/cache 
mount -o defaults,noatime,compress-force=zstd,subvol=@repos /dev/mapper/cryptroot /mnt/gentoo/var/db/repos 
mkdir /mnt/gentoo/var/cache/binpkgs
mount -o defaults,noatime,compress-force=zstd,subvol=@binpkgs /dev/mapper/cryptroot /mnt/gentoo/var/cache/binpkgs 
mkswap /dev/nvme0n1p2 
swapon /dev/nvme0n1p2 
```
download the tarball and extract it 
```
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo 
```
prepare system and chroot 
```
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc 
mount --rbind /sys /mnt/gentoo/sys 
mount --rbind /dev /mnt/gentoo/dev 
mount --bind /run /mnt/gentoo/run 
mount --make-slave /mnt/gentoo/run 
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm 
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm /run/shm 
chroot /mnt/gentoo /bin/bash 
source /etc/profile 
export PS1="(chroot) ${PS1}" 
```
Install Gentoo snapshot
```
emerge-webrsync
```
edit the make.conf, just use flags we will recompile everything with new cflags and lto later, I personally also like to use the mold linker so I will be reocmpiling everything after creating a kernel. \
Here are mine for reference
```
USE="-systemd -X wayland pipewire vaapi pgo graphite lto -llvm -clang nvidia"
```
preparing for the dinit profile
```
emerge --ask --oneshot app-portage/cpuid2cpuflags 
emerge -aqv eselect-repository 
mkdir /etc/portage/repos.conf 
cat /usr/share/portage/cofig/repos.conf > /etc/portage/repos.conf/eselect-repo.conf 
eselect repository add mez-overlay git https://github.com/KCIRREM/mez-overlay.git 
echo "priority = 999" >> /etc/portage/repos.conf/eselect-repo.conf 
eselect profile list 
```
select the dinit one 
```
eselect profile set 77 
```
replace VIDEO_CARDS with your own
```
echo "CPU_FLAGS_X86=\"$(cpuid2cpuflags | sed 's/.*://g')\"" >> /etc/portage/make.conf 
echo -e 'ACCEPT_LICENSE="*"\nVIDEO_CARDS="amdgpu radeonsi nvidia"' 
```
Set timezone
```
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime 
```
set locale 
```
echo -e "en_GB ISO-8859-1\nen_GB.UTF-8 UTF-8" >> /etc/locale.gen 
eselect locale list 
eselect locale set 4 
env-update && source /etc/profile && export PS1="(chroot) ${PS1}" 
```
update world to reflect new profile 
```
emerge --ask --verbose --update --deep --changed-use @world 
emerge --ask --depclean 
```
I will be doing a manual kernel comp follow the wiki for distribution
```
emerge --ask sys-fs/crypt-setup sys-fs/btrfs-progs app-arch/lz4
emerge --ask sys-kernel/linux-firmware 
emerge --ask sys-firmware/sof-firmware 
emerge --ask sys-kernel/installkernel 
```
clone this repo and copy appropriate files into install kernel 
```
git clone https://github.com/KCIRREM/Gentoo-Install-Guide.git 
cp -r Gentoo-Install-Guide/configs/kernel/installkernel/ /etc/kernel/ 
mkdir -p /efi/EFI/Gentoo 
emerge --ask sys-kernel/gentoo-sources 
```
I've already got a config but I'll make a guide or something here 
```
cd /usr/src/linux 
make -j8 && make -j8 modules_install 
make install 
```
now we need to sort out all of the dinit scripts 
```
cp -r /Gentoo-Install-Scripts/configs/dinit /etc/
mkdir /etc/dinit/boot.d
ln -s /etc/dinit.d/late-filesystems /etc/dinit.d/boot.d/late-filesystems
```
install any additional scripts here, for me thats:
```
ln -s /etc/dinit.d/chrony /etc/dinit.d/boot.d/chrony
ln -s /etc/dinit.d/dbusd /etc/dinit.d/boot.d/dbusd
ln -s /etc/dinit.d/dhcpcd /etc/dinit.d/boot.d/dhcpcd
ln -s /etc/dinit.d/iwd /etc/dinit.d/boot.d/iwd
ln -s /etc/dinit.d/seatd /etc/dinit.d/boot.d/seatd

```
Install system utilities
for seatd we need to use the useflag server, no elogind
```
echo "sys-auth/seatd server" > /etc/portage/package.use/seatd"
```
Install packages
```
emerge -av iwd net-wireless/iwd sys-apps/dbus sys-auth/seatd net-misc/chrony net-misc/dhcpcd app-admin/sysklogd
```
Reboot and you should have a working system
