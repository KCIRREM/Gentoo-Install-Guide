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
mount -o defaults,noatime,compress-force=zstd,subvol=@ /dev/nvme0n1p3 /mnt/gentoo/
cd /mnt/gentoo
mkdir ./{home,.snapshots,var,efi}
mkdir ./var/{cache,db,log,tmp}
mkdir ./var/db/repos
mkdir ./var/cache/binpkgs
mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o defaults,noatime,compress-force=zstd,subvol=@home /dev/nvme0n1p3 /mnt/gentoo/home
mount -o defaults,noatime,compress-force=zstd,subvol=@.snapshots /dev/nvme0n1p3 /mnt/gentoo/home/.snapshots
mount -o defaults,noatime,compress-force=zstd,subvol=@tmp /dev/nvme0n1p3 /mnt/gentoo/var/tmp
mount -o defaults,noatime,compress-force=zstd,subvol=@log /dev/nvme0n1p3 /mnt/gentoo/var/log
mount -o defaults,noatime,compress-force=zstd,subvol=@cache /dev/nvme0n1p3 /mnt/gentoo/var/cache
mount -o defaults,noatime,compress-force=zstd,subvol=@repos /dev/nvme0n1p3 /mnt/gentoo/var/db/repos
mount -o defaults,noatime,compress-force=zstd,subvol=@binpkgs /dev/nvme0n1p3 /mnt/gentoo/cache/binpkgs
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2

download tarball

tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo




