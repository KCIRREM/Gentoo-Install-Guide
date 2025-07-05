# Gentoo-Install-Guide
An encrypted Gentoo install with btrfs and subvolumes along withe efistub as the bootloader.

500M, 19GB, rest is root
efi partiton, swap, luks on btrfs

format appropriately
cryptsetup luksFormat --key-size 512 /dev/nvme0n1p3
cryptsetup luksOpen /dev/nvme0n1p3 cryptroot
mkfs.btrfs /dev/mapper/cryptroot
mkdir -p /mnt/gentoo
mount /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo
btrfs subvol create {@,@home,@tmp,@cache,@repos,@log,@binpkgs,@snapshots}
cd ../
umount /mnt/gentoo
mount -o defaults,noatime,compress-force=zstd,subvol=@ /dev/mapper/cryptroot /mnt/gentoo/
cd /mnt/gentoo
mkdir ./{home,.snapshots,var,efi}
mkdir ./var/{cache,db,log,tmp}
mkdir ./var/db/repos
mkdir ./var/cache/binpkgs
mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o defaults,noatime,compress-force=zstd,subvol=@home /dev/mapper/cryptroot /mnt/gentoo/home
mount -o defaults,noatime,compress-force=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/gentoo/.snapshots
mount -o defaults,noatime,compress-force=zstd,subvol=@tmp /dev/mapper/cryptroot /mnt/gentoo/var/tmp
mount -o defaults,noatime,compress-force=zstd,subvol=@log /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o defaults,noatime,compress-force=zstd,subvol=@cache /dev/mapper/cryptroot /mnt/gentoo/var/cache
mount -o defaults,noatime,compress-force=zstd,subvol=@repos /dev/mapper/cryptroot /mnt/gentoo/var/db/repos
mount -o defaults,noatime,compress-force=zstd,subvol=@binpkgs /dev/mapper/cryptroot /mnt/gentoo/var/cache/binpkgs
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2

download tarball

tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys 
mount --rbind /dev /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run 
mount --make-slave /mnt/gentoo/run
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm 
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm 
chmod 1777 /dev/shm /run/shm
chroot /mnt/gentoo /bin/bash 
source /etc/profile 
export PS1="(chroot) ${PS1}"
emerge-webrsync
emerge -aqv eselect-repository
eselect repository enable gentoo
eselect repository add mez-overlay git https://github.com/KCIRREM/mez-overlay.git

file in /etc/portage/repos.conf/eselect-repo.conf shoul llok like this
# created by eselect-repo
[mez-overlay]
priority = 999 
location = /var/db/repos/mez-overlay

[gentoo]
location = /var/db/repos/gentoo
sync-type = git
sync-uri = https://github.com/gentoo-mirror/gentoo.git

add the priority 999 to my overlay

emerge -C sys-apps/openrc
emerge -C sys-apps/sysvinit
emerge --oneshot -av virtuals/service-manager
eselect profile list

select the dinit one

eselect profile set 77

clone this repo to get the make files

emerge --ask --oneshot app-portage/cpuid2cpuflags
replace my cpuid flags in my make.conf with the output of your cpuid2cpuflags
do the same for video cards (read wiki)
emerge gcc again to enable lto, pgo and graphite this may take a while
emerge --ask --oneshot sys-devel/gcc

replace your make with the final (enabling lto and stuff)
update world set to reflect our flags
emerge --ask --verbose --update --deep --changed-use @world
emerge --ask --depclean
ln -sf ../usr/share/zoneinfo/Europe/London /etc/localtime
echo "en_GB ISO-8859-1" >> /etc/locale.gen; echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
eselect locale list
select the right one
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

I will be doing a manual kernel comp follow the wiki for distribution
emerge --ask sys-kernel/linux-firmware
emerge --ask sys-firmware/sof-firmware









