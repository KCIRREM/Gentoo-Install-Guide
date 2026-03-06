# 🐧 Gentoo Linux Install Guide

An opinionated guide to installing Gentoo Linux from scratch.
This guide targets **x86_64**, **UEFI boot**, **dinit**, and a **musl + LLVM/Clang** toolchain.

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
8. [Bootstrapping Rust & Java](#8-bootstrapping-rust--java)
9. [Networking](#9-networking)
10. [Final Steps & First Boot](#10-final-steps--first-boot)

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

Gentoo can be installed from any live Linux environment — you don't need the official Gentoo ISO. I'd recommend **Linux Mint** as the live environment since hardware support tends to be excellent out of the box, and it provides a full desktop to work from.

https://www.linuxmint.com/download.php

Download the latest **Cinnamon** edition. Any other edition works too — the desktop doesn't matter since we're just using it as a launchpad.

> ℹ️ If you're already running a Linux system and are comfortable working from it directly, you can skip the live USB entirely and work from your existing install.

### 1.2 Write to USB

**Linux**
```bash
# Replace /dev/sdX with your USB device — double check with lsblk first!
dd if=linuxmint-<version>-cinnamon-64bit.iso of=/dev/sdX bs=4M status=progress && sync
```

**Windows / macOS**
Use [Rufus](https://rufus.ie/) (Windows) or [Balena Etcher](https://etcher.balena.io/) (cross-platform).

### 1.3 Boot the Live Environment

1. Insert the USB and reboot
2. Enter your UEFI firmware (usually `F2`, `F12`, `Del`, or `Esc` at POST)
3. Disable **Secure Boot** if prompted
4. Set boot order to USB first
5. Save and reboot

You should land at the Linux Mint desktop. Open a terminal and become root.

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

> ⚠️ **All data on the target disk will be destroyed.** Double-check you have the right device.

### 2.2 Partition Layout

| Partition | Size | Type | Mount |
|---|---|---|---|
| `/dev/nvme0n1p1` | 512 MB | EFI System | `/boot/efi` |
| `/dev/nvme0n1p2` | Remainder | LUKS2 container → btrfs | `/` |

> **Swap size:** Match your RAM for hibernation support, otherwise 2–4 GB is fine.

### 2.3 Partition the Disk

```bash
fdisk /dev/nvme0n1
Command (m for help): g
Created a new GPT disklabel
Command (m for help): n
Partition number (1-128, default 1): 
First sector (2048-999163870, default 2048): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-999163870, default 999161855): +512M
Command (m for help): t
Partition type or alias (type L to list all): 1
Command (m for help): n
Partition number (2-128, default 2): 
First sector (1050624-999163870, default 1050624): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (1050624-999163870, default 999161855):
Command (m for help): w
```

### 2.4 Format the Partitions

```bash
mkfs.fat -F32 /dev/nvme0n1p1
cryptsetup luksFormat /dev/nvme0n1p2
cryptsetup luksOpen /dev/nvme0n1p2 cryptroot
mkfs.btrfs -L gentoo /dev/mapper/cryptroot
```

### 2.5 Create Btrfs Subvolumes

```bash
# Mount root temporarily to create subvolumes
mkdir /mnt/gentoo
mount /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo
btrfs subvol create {@swap,@,@home,@tmp,@cache,@repos,@log,@snapshots}
cd .. && umount /mnt/gentoo/
```

### 2.6 Mount with Subvolume Flags

```bash
BTRFS_OPTS="compress=zstd:3,noatime,space_cache=v2,discard=async"
mount -o ${BTRFS_OPTS},subvol=@ /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo
mkdir swap home .snapshots efi
mkdir -p var/{cache,db/repos,log,tmp}
mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o noatime,discard=async,nodatacow,subvol=@swap /dev/mapper/cryptroot /mnt/gentoo/swap
mount -o ${BTRFS_OPTS},subvol=@home /dev/mapper/cryptroot /mnt/gentoo/home
mount -o ${BTRFS_OPTS},subvol=@snapshots /dev/mapper/cryptroot /mnt/gentoo/.snapshots
mount -o ${BTRFS_OPTS},subvol=@log /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o noatime,discard=async,nodatacow,subvol=@tmp /dev/mapper/cryptroot /mnt/gentoo/var/tmp
mount -o ${BTRFS_OPTS},subvol=@cache /dev/mapper/cryptroot /mnt/gentoo/var/cache
mount -o ${BTRFS_OPTS},subvol=@repos /dev/mapper/cryptroot /mnt/gentoo/var/db/repos
btrfs filesystem mkswapfile --size 64g --uuid clear swap/swapfile
swapon /mnt/gentoo/swap/swapfile
chattr +C var/tmp/
```

Verify:
```bash
lsblk
```

---

## 3. Stage 3 & Portage

Navigate to the [Gentoo downloads page](https://www.gentoo.org/downloads/amd64/#stages-advanced) and select the **musl llvm** stage 3, then move it into `/mnt/gentoo`.

```bash
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo
```

---

## 4. Chroot & Base Config

```bash
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm /run/shm
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) ${PS1}"
emerge-webrsync
mkdir /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
```

---

## 5. Profiles, Locales & Timezones

We need to set up the custom dinit/mdevd profile before configuring make.conf. The profile sets a number of USE flags itself, so enabling it first avoids conflicts when we do our initial world update in the next section.

First, install `eselect-repository` and enable the required repositories:

```bash
emerge eselect-repository
eselect repository add musl-dinit git https://github.com/KCIRREM/musl-dinit.git
eselect repository enable guru
eselect repository enable CachyOS-kernels  # Optional — you can use the standard Gentoo kernel instead
emaint sync
```

Now set up locales and timezone:

```bash
emerge sys-apps/musl-locales sys-libs/timezone-data
echo 'MUSL_LOCPATH="/usr/share/i18n/locales/musl"' > /etc/env.d/00local

# Set your timezone — browse /usr/share/zoneinfo/ to find yours
echo 'TZ="/usr/share/zoneinfo/Europe/London"' >> /etc/env.d/00local
source /etc/profile

eselect locale list
eselect locale set <N>  # Choose the number corresponding to your preferred locale
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
```

Optionally, patch musl with the mimalloc allocator (sourced from Chimera Linux via my repo) for improved allocation performance:

```bash
echo "sys-libs/musl mimalloc" > /etc/portage/package.use/musl
echo "sys-apps/file -seccomp" >> /etc/portage/package.use/musl
emerge -av1 sys-libs/musl sys-apps/file
```

Now select the dinit/mdevd profile and run the initial world update:

```bash
eselect profile list
eselect profile set <N>  # Find and select the dinit mdevd profile from the musl-dinit repository
emerge -avuDN @world
emerge --depclean
```
---

## 6. Make.conf & World Rebuild

> ℹ️ **Why does make.conf come here?** We needed the custom profile installed and the initial `@world` update complete first. The profile sets its own USE flags, and applying our custom compiler flags before that point can cause collisions. Now that the profile is stable, we can layer our optimised flags on top and do a full rebuild.

Below is an example `make.conf` — adjust `MAKEOPTS`, `VIDEO_CARDS`,`CPU_FLAGS_X86` and `USE` to match your hardware and preferences.

```bash
COMMON_FLAGS="-O3 -pipe -march=native -flto=thin -fno-semantic-interposition"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="-C target-cpu=native -C strip=debuginfo -C opt-level=3 -Clinker=clang -Clinker-plugin-lto -Clink-arg=-fuse-ld=lld"

# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult https://wiki.gentoo.org/wiki/Changing_the_CHOST_variable before changing.
CHOST="x86_64-pc-linux-musl"

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C.UTF-8

GENTOO_MIRRORS="https://mirrors.gethosted.online/gentoo/ \
    https://www.mirrorservice.org/sites/distfiles.gentoo.org/ \
    rsync://rsync.mirrorservice.org/distfiles.gentoo.org/"

MAKEOPTS="-j16"
ACCEPT_LICENSE="*"
VIDEO_CARDS="amdgpu radeonsi nvidia"
CPU_FLAGS_X86="aes avx avx2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3"

USE="-systemd -X wayland pipewire vaapi nvidia dbus -elogind seatd -logind"
```

With the new flags in place, rebuild the entire system to ensure everything is compiled with your optimised settings. This step takes a long time — it's a good one to kick off before going to sleep.

```bash
emerge -e1 @world
```

---

## 7. Bootloader & Kernel

This guide uses efistub via `ugrd` for a minimal boot setup. If you'd prefer GRUB or another bootloader, refer to the [Gentoo Wiki](https://wiki.gentoo.org).

```bash
echo "sys-kernel/installkernel efistub ugrd" > /etc/portage/package.use/installkernel
emerge sys-fs/cryptsetup sys-fs/btrfs-progs app-arch/lz4 sys-kernel/linux-firmware sys-firmware/sof-firmware sys-kernel/installkernel
echo "musl_libc = true" > /etc/ugrd/config.toml
```

This guide uses the CachyOS kernel sources. If you'd prefer the standard Gentoo sources, substitute `cachyos-sources` with `gentoo-sources` and skip the keyword/USE entries.

```bash
echo "sys-kernel/cachyos-sources ~amd64" > /etc/portage/package.accept_keywords/cachy-sources
# The autofdo and propeller flags require a supported CPU — omit them if unsure
echo "sys-kernel/cachyos-sources -autofdo -propeller" > /etc/portage/package.use/cachy-sources
mkdir -p /efi/EFI/Gentoo
emerge sys-kernel/cachyos-sources
```

Build and install the kernel. If you want to customise the configuration, run `make LLVM=1 LLVM_IAS=1 nconfig` first and skip oldfeconfig.

```bash
make LLVM=1 LLVM_IAS=1 olddefconfig
make LLVM=1 LLVM_IAS=1 -j16
make -j16 modules_install
make install
```

---

## 8. Bootstrapping Rust & Java

Gentoo does not provide prebuilt Rust or Java packages for musl + LLVM systems, which creates a circular dependency — many packages need Rust or Java to build, but Rust and Java themselves need to be compiled first. The solution is to build them in a temporary musl libstdc++-based chroot, then switch profiles and rebuild them with libcxx to produce binary packages, and then install those into the main system. This approach is based on the [Gentoo Wiki's guide to bootstrapping Rust via stage file](https://wiki.gentoo.org/wiki/Bootstrapping_Rust_via_stage_file).

```bash
emerge fakeroot
mkdir ~/gentoo-rootfs

cat << 'EOF' > ~/gentoo-rootfs/bootstrap.sh
#!/bin/bash
source /etc/profile
emerge-webrsync
emerge llvm-core/clang llvm-core/llvm llvm-runtimes/compiler-rt llvm-runtimes/libunwind llvm-core/lld dev-lang/rust dev-java/openjdk
eselect profile set default/linux/amd64/23.0/musl/llvm  # Adjust to whichever musl/llvm profile is current
source /etc/profile
emerge llvm-runtimes/clang-runtime
emerge llvm-core/clang llvm-core/llvm llvm-runtimes/libcxx llvm-runtimes/libcxxabi llvm-runtimes/compiler-rt llvm-runtimes/compiler-rt-sanitizers llvm-runtimes/libunwind llvm-core/lld
emerge --buildpkg dev-lang/rust dev-java/openjdk
EOF

cd ~/gentoo-rootfs

# Update this URL to the latest musl openrc stage3 from https://www.gentoo.org/downloads/
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/20260302T174559Z/stage3-amd64-musl-openrc-20260302T174559Z.tar.xz

fakeroot tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cp --dereference /etc/resolv.conf ~/gentoo-rootfs/etc/
mount --types proc /proc ~/gentoo-rootfs/proc
mount --rbind /sys ~/gentoo-rootfs/sys
mount --make-rslave ~/gentoo-rootfs/sys
mount --rbind /dev ~/gentoo-rootfs/dev
mount --make-rslave ~/gentoo-rootfs/dev
mount --bind /run ~/gentoo-rootfs/run
mount --make-slave ~/gentoo-rootfs/run
chroot ~/gentoo-rootfs /bin/bash /bootstrap.sh

[ -d /var/cache/binpkgs ] && mv /var/cache/binpkgs /var/cache/binpkgs-tmp
cp -r ./var/cache/binpkgs /var/cache/binpkgs
emerge --usepkg dev-lang/rust dev-java/openjdk
```

Now rebuild those packages with the optimised flags from your make.conf. LTO must be disabled for Rust specifically, as it manages its own LTO pipeline:

```bash
mkdir /etc/portage/env/

cat << 'EOF' > /etc/portage/env/no-lto.conf
COMMON_FLAGS="-O3 -pipe -march=native -fno-semantic-interposition -fno-common"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
RUSTFLAGS="-C target-cpu=native -C strip=debuginfo -C opt-level=3 -Clinker=clang -Clink-arg=-fuse-ld=lld"
EOF

echo "dev-lang/rust no-lto.conf" > /etc/portage/package.env
echo "dev-lang/rust lto" > /etc/portage/package.use
emerge dev-lang/rust dev-java/openjdk
```

---

## 9. Networking

> 🚧 This section is a work in progress.

---

## 10. Final Steps & First Boot

> 🚧 This section is a work in progress.

---

## Contributing

Found an error or have an improvement? Open an issue or submit a pull request.
Please note which section and whether you're on different hardware or a different configuration than listed above.

---

## Resources

- [Official Gentoo Handbook (AMD64)](https://wiki.gentoo.org/wiki/Handbook:AMD64)
- [Gentoo Wiki](https://wiki.gentoo.org)
- [Gentoo Forums](https://forums.gentoo.org)
- [dinit documentation](https://davmac.org/projects/dinit/)
- [Gentoo musl wiki](https://wiki.gentoo.org/wiki/Project:Musl)
