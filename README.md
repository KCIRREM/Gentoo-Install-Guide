# 🐧 Gentoo Linux Install Guide

An opinionated guide to installing Gentoo Linux from scratch.
Targets **x86_64**, **UEFI boot**, **dinit**, and a **musl + LLVM/Clang** toolchain.

> **Last verified:** March 2025 · Based on Gentoo Handbook (AMD64)

---

## Table of Contents

1. [Preparation & Booting](#1-preparation--booting)
2. [Disk Partitioning](#2-disk-partitioning)
3. [Stage 3 & Portage](#3-stage-3--portage)
4. [Chroot & Base Config](#4-chroot--base-config)
5. [Profiles, Locales & Timezones](#5-profiles-locales--timezones)
6. [Make.conf & World Rebuild](#6-makeconf--world-rebuild)
7. [Bootloader & Kernel](#7-bootloader--kernel)
8. [System Configuration](#8-system-configuration)
9. [System Utilities](#9-system-utilities)
10. [Bootstrapping Rust & Java](#10-bootstrapping-rust--java)
11. [Final Steps & First Boot](#11-final-steps--first-boot)

---

## Prerequisites

- A USB drive (≥ 1 GB) for the live environment
- A target disk (≥ 20 GB recommended)
- An internet connection during install
- Basic comfort with the Linux command line

## Configuration

This guide uses a minimal, modern stack — musl instead of glibc for a leaner
base, LLVM/Clang as the primary toolchain, dinit for init and service
management, and mdevd in place of udev. Storage is btrfs with subvolumes
for easy snapshotting.

- **Architecture:** x86_64, UEFI
- **Libc:** musl (`stage3-amd64-musl`)
- **Toolchain:** LLVM/Clang
- **Init:** dinit
- **Device manager:** mdevd
- **Filesystem:** LUKS2 encryption, btrfs with subvolumes (`@`, `@home`, `@cache`, `@log`, `@tmp`, `@swap`, `@repos`, `@snapshots`), FAT32 (EFI)
- **Profile:** default/linux/amd64/musl

> ⚠️ **Note:** The musl and LLVM/Clang profiles are not officially supported by Gentoo. You may encounter packages that fail to build or behave unexpectedly.

---

## 1. Preparation & Booting

### 1.1 Download the Installation Media

Gentoo can be installed from any live Linux environment. **Linux Mint** is a good choice — hardware support is broad and you get a full desktop to work from.

https://www.linuxmint.com/download.php

Download the latest **Cinnamon** edition. The desktop choice doesn't matter since we're just using it as a launchpad.

> ℹ️ If you're already on a Linux system, you can skip the live USB and work from your existing install.

### 1.2 Write to USB

**Linux**
```bash
# Verify the device with lsblk before running this
dd if=linuxmint-<version>-cinnamon-64bit.iso of=/dev/sdX bs=4M status=progress && sync
```

**Windows / macOS**
Use [Rufus](https://rufus.ie/) (Windows) or [Balena Etcher](https://etcher.balena.io/) (cross-platform).

### 1.3 Boot the Live Environment

1. Insert the USB and reboot
2. Enter your UEFI firmware (usually `F2`, `F12`, `Del`, or `Esc` at POST)
3. Disable **Secure Boot**
4. Set boot order to USB first
5. Save and reboot

Once at the Linux Mint desktop, open a terminal and `sudo su` to become root.

---

## 2. Disk Partitioning

### 2.1 Identify Your Target Disk

```bash
lsblk
```

Common device names:
- `/dev/sda` — SATA/USB drives
- `/dev/nvme0n1` — NVMe SSDs
- `/dev/vda` — Virtual machines

> ⚠️ **All data on the target disk will be destroyed.** Double-check you have the right device before proceeding.

### 2.2 Partition Layout

| Partition | Size | Type | Mount |
|---|---|---|---|
| `/dev/nvme0n1p1` | 512 MB | EFI System | `/efi` |
| `/dev/nvme0n1p2` | Remainder | LUKS2 container → btrfs | `/` |

> **Swap:** A btrfs swapfile is created inside the `@swap` subvolume rather than a dedicated partition. Size it to match your RAM if you want hibernation support, otherwise 2–4 GB is fine.

### 2.3 Partition the Disk

```bash
fdisk /dev/nvme0n1
```

Inside fdisk:
```
g        # create new GPT disklabel
n        # new partition (EFI)
          # accept defaults for partition number and first sector
+512M    # size
t        # change type
1        # EFI System
n        # new partition (root)
          # accept all defaults (fills remaining space)
w        # write and exit
```

### 2.4 Format the Partitions

```bash
mkfs.fat -F32 /dev/nvme0n1p1
cryptsetup luksFormat /dev/nvme0n1p2   # you'll be prompted to set a passphrase
cryptsetup luksOpen /dev/nvme0n1p2 cryptroot
mkfs.btrfs -L gentoo /dev/mapper/cryptroot
```

### 2.5 Create Btrfs Subvolumes

```bash
mkdir /mnt/gentoo
mount /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo
btrfs subvol create {@swap,@,@home,@tmp,@cache,@repos,@log,@snapshots}
cd .. && umount /mnt/gentoo
```

### 2.6 Mount with Subvolume Flags

```bash
BTRFS_OPTS="compress=zstd:3,noatime,space_cache=v2,discard=async"

mount -o ${BTRFS_OPTS},subvol=@ /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo

mkdir swap home .snapshots efi
mkdir -p var/{cache,db/repos,log,tmp}

mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o noatime,discard=async,nodatacow,subvol=@swap    /dev/mapper/cryptroot /mnt/gentoo/swap
mount -o ${BTRFS_OPTS},subvol=@home                      /dev/mapper/cryptroot /mnt/gentoo/home
mount -o ${BTRFS_OPTS},subvol=@snapshots                 /dev/mapper/cryptroot /mnt/gentoo/.snapshots
mount -o ${BTRFS_OPTS},subvol=@log                       /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o noatime,discard=async,nodatacow,subvol=@tmp     /dev/mapper/cryptroot /mnt/gentoo/var/tmp
mount -o ${BTRFS_OPTS},subvol=@cache                     /dev/mapper/cryptroot /mnt/gentoo/var/cache
mount -o ${BTRFS_OPTS},subvol=@repos                     /dev/mapper/cryptroot /mnt/gentoo/var/db/repos

# nodatacow is important for var/tmp and swap — CoW interacts badly with frequently-rewritten files
chattr +C /mnt/gentoo/var/tmp/

# Create the swapfile — adjust size to taste
btrfs filesystem mkswapfile --size 16g --uuid clear /mnt/gentoo/swap/swapfile
swapon /mnt/gentoo/swap/swapfile
```

Verify the layout:
```bash
lsblk
```

---

## 3. Stage 3 & Portage

Navigate to the [Gentoo downloads page](https://www.gentoo.org/downloads/amd64/#stages-advanced) and grab the **musl llvm** stage 3 tarball, then move it into `/mnt/gentoo`.

```bash
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
```
---

## 4. Chroot & Base Config

Bind-mount the required virtual filesystems and enter the chroot:

```bash
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys && mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev && mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run && mount --make-slave /mnt/gentoo/run

# Fix /dev/shm if it's a symlink (common on some live environments)
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm /run/shm

chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"
```

Sync the Portage tree:
```bash
emerge-webrsync
mkdir /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
```

---

## 5. Profiles, Locales & Timezones

The custom dinit/mdevd profile must be selected **before** `make.conf` is customised. The profile sets its own USE flags; applying custom compiler flags before that point risks collisions on the initial `@world` update.

Add the required repositories:

```bash
emerge eselect-repository
eselect repository add musl-dinit git https://github.com/KCIRREM/musl-dinit.git
eselect repository enable guru
eselect repository enable CachyOS-kernels  # optional — skip if using gentoo-sources
emaint sync
```

Set up locales and timezone:

```bash
emerge sys-apps/musl-locales sys-libs/timezone-data
echo 'MUSL_LOCPATH="/usr/share/i18n/locales/musl"' > /etc/env.d/00local

# Browse /usr/share/zoneinfo/ to find your zone
echo 'TZ="/usr/share/zoneinfo/Europe/London"' >> /etc/env.d/00local
source /etc/profile

eselect locale list
eselect locale set <N>
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
```

Optionally, patch musl with the mimalloc allocator (sourced from Chimera Linux) for improved allocation performance:

```bash
echo "sys-libs/musl mimalloc" > /etc/portage/package.use/musl
echo "sys-apps/file -seccomp" >> /etc/portage/package.use/musl
emerge -av1 sys-libs/musl sys-apps/file
```

Select the dinit/mdevd profile and run the initial world update. This will take a while:

```bash
eselect profile list
eselect profile set <N>   # find the dinit mdevd profile from the musl-dinit repository
emerge -avuDN @world
emerge --depclean
```

---

## 6. Make.conf & World Rebuild

Layer your optimised flags on top and do a full rebuild.

Below is an example `make.conf` — adjust `MAKEOPTS`, `VIDEO_CARDS`, `CPU_FLAGS_X86`, and `USE` for your hardware.

```bash
# /etc/portage/make.conf

COMMON_FLAGS="-O3 -pipe -march=native -flto=thin -fno-semantic-interposition"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="-C target-cpu=native -C strip=debuginfo -C opt-level=3 -Clinker=clang -Clinker-plugin-lto -Clink-arg=-fuse-ld=lld"

# WARNING: Do not change CHOST after initial build without reading:
# https://wiki.gentoo.org/wiki/Changing_the_CHOST_variable
CHOST="x86_64-pc-linux-musl"

LC_MESSAGES=C.UTF-8

GENTOO_MIRRORS="https://mirrors.gethosted.online/gentoo/ \
    https://www.mirrorservice.org/sites/distfiles.gentoo.org/ \
    rsync://rsync.mirrorservice.org/distfiles.gentoo.org/"

MAKEOPTS="-j16"   # set to nproc, or nproc-1 if the system becomes unusable during builds
ACCEPT_LICENSE="*"

# Set to match your GPU
VIDEO_CARDS="amdgpu radeonsi"

# Generate with: cpuid2cpuflags
CPU_FLAGS_X86="aes avx avx2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3"

USE="-systemd -X wayland pipewire vaapi dbus -elogind seatd -logind"
```

Rebuild the world with the new flags. This is a good one to kick off before sleeping:

```bash
emerge -e1 @world
```

---

## 7. Bootloader & Kernel

This guide uses efistub via `ugrd` for a minimal boot setup. For GRUB or other bootloaders, refer to the [Gentoo Wiki](https://wiki.gentoo.org).

```bash
echo "sys-kernel/installkernel efistub ugrd" > /etc/portage/package.use/installkernel
emerge sys-fs/cryptsetup sys-fs/btrfs-progs app-arch/lz4 \
    sys-kernel/linux-firmware sys-firmware/sof-firmware \
    sys-kernel/installkernel

echo "musl_libc = true" > /etc/ugrd/config.toml
```

This guide uses CachyOS kernel sources. Substitute `cachyos-sources` with `gentoo-sources` and skip the keyword/USE entries if you prefer the standard kernel:

```bash
echo "sys-kernel/cachyos-sources ~amd64" > /etc/portage/package.accept_keywords/cachyos-sources
# autofdo and propeller require a supported CPU — omit if unsure
echo "sys-kernel/cachyos-sources -autofdo -propeller" > /etc/portage/package.use/cachyos-sources
mkdir -p /efi/EFI/Gentoo
emerge sys-kernel/cachyos-sources
```

Build and install. Run `make LLVM=1 LLVM_IAS=1 nconfig` first if you want to customise the config:

```bash
cd /usr/src/linux
make LLVM=1 LLVM_IAS=1 olddefconfig
make LLVM=1 LLVM_IAS=1 -j$(nproc)
make -j$(nproc) modules_install
make install
```

---

## 8. System Configuration

### 8.1 Fstab

```bash
emerge -av1 genfstab
genfstab -U / > /etc/fstab
```

Review `/etc/fstab` after generating — genfstab is reliable but it's worth a sanity check. A correct fstab for this layout looks like:

```
# /dev/mapper/cryptroot LABEL=gentoo
UUID=<uuid>   /              btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@           0 0
UUID=<uuid>   /home          btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@home       0 0
UUID=<uuid>   /swap          btrfs   rw,noatime,ssd,discard=async,subvol=/@swap                                      0 0
UUID=<uuid>   /.snapshots    btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@snapshots  0 0
UUID=<uuid>   /var/log       btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@log        0 0
UUID=<uuid>   /var/tmp       btrfs   rw,noatime,ssd,discard=async,subvol=/@tmp                                       0 0
UUID=<uuid>   /var/cache     btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@cache      0 0
UUID=<uuid>   /var/db/repos  btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@repos      0 0

# /dev/nvme0n1p1
UUID=<uuid>   /efi           vfat    rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=iso8859-1,shortname=mixed,errors=remount-ro   0 2

/swap/swapfile   none   swap   defaults   0 0
```

### 8.2 Hostname & Network

We're not using udev, so NetworkManager isn't an option here. `dhcpcd` handles wired; `iwd` handles Wi-Fi.

```bash
echo "myhostname" > /etc/hostname
emerge net-misc/dhcpcd-dinit net-wireless/iwd-dinit
```

Since dinit isn't running inside the chroot yet, enable services by symlinking them into `boot.d` directly:

```bash
ln -sr /usr/lib/dinit.d/dhcpcd /usr/lib/dinit.d/boot.d/
ln -sr /usr/lib/dinit.d/iwd /usr/lib/dinit.d/boot.d/
```

### 8.3 Root Password

```bash
passwd
```

---

## 9. System Utilities

Install and enable a basic set of system utilities:

```bash
emerge \
    app-admin/syslog-ng-dinit \
    sys-process/fcron-dinit \
    app-admin/logrotate \
    sys-apps/mlocate \
    app-shells/bash-completion \
    net-misc/chrony-dinit

ln -sr /usr/lib/dinit.d/syslog-ng /usr/lib/dinit.d/boot.d/
ln -sr /usr/lib/dinit.d/fcron /usr/lib/dinit.d/boot.d/
ln -sr /usr/lib/dinit.d/chrony /usr/lib/dinit.d/boot.d/
```

What each package provides:
- **syslog-ng** — system logger
- **fcron** — cron daemon compatible with musl
- **logrotate** — log rotation (driven by fcron)
- **mlocate** — `locate` file index
- **bash-completion** — tab completion
- **chrony** — NTP client/server, handles time sync

---

## 10. Bootstrapping Rust & Java

Gentoo doesn't provide prebuilt Rust or Java packages for musl + LLVM systems. This creates a circular dependency — many packages need Rust or Java to build, but those runtimes must themselves be compiled. The solution is to build them in a temporary musl chroot using libstdc++, produce binary packages, then install those into the main system.

This approach follows the [Gentoo Wiki's bootstrapping Rust via stage file](https://wiki.gentoo.org/wiki/Bootstrapping_Rust_via_stage_file).

### 10.1 Set Up the Bootstrap Chroot

```bash
emerge fakeroot
mkdir ~/gentoo-rootfs

# Update this URL to the latest musl openrc stage3 from https://www.gentoo.org/downloads/
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20260302T174559Z/stage3-amd64-musl-openrc-20260302T174559Z.tar.xz"
wget -P ~/gentoo-rootfs "${STAGE3_URL}"

cd ~/gentoo-rootfs
fakeroot tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cp --dereference /etc/resolv.conf ~/gentoo-rootfs/etc/
```

Bind-mount into the bootstrap chroot:

```bash
mount --types proc /proc ~/gentoo-rootfs/proc
mount --rbind /sys ~/gentoo-rootfs/sys && mount --make-rslave ~/gentoo-rootfs/sys
mount --rbind /dev ~/gentoo-rootfs/dev && mount --make-rslave ~/gentoo-rootfs/dev
mount --bind /run ~/gentoo-rootfs/run && mount --make-slave ~/gentoo-rootfs/run
```

### 10.2 Write the Bootstrap Script

```bash
cat << 'EOF' > ~/gentoo-rootfs/bootstrap.sh
#!/bin/bash
set -euo pipefail
source /etc/profile

emerge-webrsync

# Build with libstdc++
emerge llvm-core/clang llvm-core/llvm llvm-runtimes/compiler-rt \
       llvm-runtimes/libunwind llvm-core/lld \
       dev-lang/rust dev-java/openjdk

# Switch to the musl/llvm profile — adjust to the current profile name
eselect profile set default/linux/amd64/23.0/musl/llvm
source /etc/profile

# Now rebuild the LLVM stack against libcxx
emerge llvm-runtimes/clang-runtime
emerge llvm-core/clang llvm-core/llvm \
       llvm-runtimes/libcxx llvm-runtimes/libcxxabi \
       llvm-runtimes/compiler-rt llvm-runtimes/compiler-rt-sanitizers \
       llvm-runtimes/libunwind llvm-core/lld

# Produce binary packages for installation into the main system
emerge --buildpkg dev-lang/rust dev-java/openjdk
EOF
chmod +x ~/gentoo-rootfs/bootstrap.sh
```

### 10.3 Run the Bootstrap

```bash
chroot ~/gentoo-rootfs /bin/bash /bootstrap.sh
```

### 10.4 Install Binary Packages into the Main System

Once the chroot script completes, copy the binary packages out and install them:

```bash
# Back up any existing binpkgs, then copy the bootstrap output
[ -d /var/cache/binpkgs ] && mv /var/cache/binpkgs /var/cache/binpkgs.bak
cp -r ~/gentoo-rootfs/var/cache/binpkgs /var/cache/binpkgs

emerge --usepkg dev-lang/rust dev-java/openjdk
```

### 10.5 Unmount the Bootstrap Chroot

Clean up the bind mounts:

```bash
umount -R ~/gentoo-rootfs/{proc,sys,dev,run}
```

### 10.6 Rebuild with Optimised Flags

Rust manages its own LTO pipeline, so it must be rebuilt without our rust lto flags.

```bash
mkdir -p /etc/portage/env

cat << 'EOF' > /etc/portage/env/no-lto.conf
COMMON_FLAGS="-O3 -pipe -march=native -fno-semantic-interposition -fno-common"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="-C target-cpu=native -C strip=debuginfo -C opt-level=3 -Clinker=clang -Clink-arg=-fuse-ld=lld"
EOF

echo "dev-lang/rust no-lto.conf" > /etc/portage/package.env
echo "dev-lang/rust lto" > /etc/portage/package.use/rust

emerge dev-lang/rust dev-java/openjdk
```

---

## 11. Final Steps & First Boot

> 🚧 This section is a work in progress.

Planned: user creation, LUKS key configuration, ugrd initramfs generation, and first-boot verification.

---

## Contributing

Found an error or have an improvement? Open an issue or submit a pull request.
Please note which section you're addressing and whether you're on different hardware or a different configuration.

---

## Resources

- [Official Gentoo Handbook (AMD64)](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Gentoo Wiki](https://wiki.gentoo.org)
- [Gentoo Forums](https://forums.gentoo.org)
- [dinit documentation](https://davmac.org/projects/dinit/)
- [Gentoo musl wiki](https://wiki.gentoo.org/wiki/Project:Musl)
- [Bootstrapping Rust via stage file](https://wiki.gentoo.org/wiki/Bootstrapping_Rust_via_stage_file)
