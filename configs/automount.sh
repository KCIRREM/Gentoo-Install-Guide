#! /bin/bash
current_path_abs=$(realpath $(dirname $0))
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

wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20250702T205201Z/stage3-amd64-hardened-openrc-20250702T205201Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
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
source /etc/profile 
export PS1="(chroot) ${PS1}"
