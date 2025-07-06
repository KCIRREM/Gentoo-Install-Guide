#! /bin/bash

current_path_abs=$(dirname "$(realpath $0)") 
mkdir -p /mnt/gentoo
mount -o defaults,noatime,compress-force=zstd,subvol=@ /dev/mapper/cryptroot /mnt/gentoo/

mkdir  /mnt/gentoo/{home,.snapshots,var,efi}
mkdir  /mnt/gentoo/var/{cache,db,log,tmp}
mkdir  /mnt/gentoo/var/db/repos

mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o defaults,noatime,compress-force=zstd,subvol=@home /dev/mapper/cryptroot /mnt/gentoo/home
mount -o defaults,noatime,compress-force=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/gentoo/.snapshots
mount -o defaults,noatime,compress-force=zstd,subvol=@tmp /dev/mapper/cryptroot /mnt/gentoo/var/tmp
mount -o defaults,noatime,compress-force=zstd,subvol=@log /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o defaults,noatime,compress-force=zstd,subvol=@cache /dev/mapper/cryptroot /mnt/gentoo/var/cache
mount -o defaults,noatime,compress-force=zstd,subvol=@repos /dev/mapper/cryptroot /mnt/gentoo/var/db/repos
mkdir /mnt/gentoo/var/cache/binpkgs
mount -o defaults,noatime,compress-force=zstd,subvol=@binpkgs /dev/mapper/cryptroot /mnt/gentoo/var/cache/binpkgs


pwd=$(pwd)
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20250702T205201Z/stage3-amd64-hardened-openrc-20250702T205201Z.tar.xz
cd $pwd
mv stage3-*.tar.xz /mnt/gentoo/
tar xpvf /mnt/gentoo/stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys 
mount --rbind /dev /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run 
mount --make-slave /mnt/gentoo/run
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm 
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm 
chmod 1777 /dev/shm /run/shm
cp -r $current_path_abs /mnt/gentoo/
chroot /mnt/gentoo /bin/bash 
