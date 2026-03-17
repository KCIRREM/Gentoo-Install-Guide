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
10. [Seat Management](#10-seat-management)
11. [Bootstrapping Rust & Java](#11-bootstrapping-rust--java)
12. [User Setup & Privilege Escalation](#12-user-setup--privilege-escalation)
13. [Final Steps & First Boot](#13-final-steps--first-boot)
14. [Graphics — Mesa Drivers](#14-graphics--mesa-drivers)
15. [Audio — PipeWire & WirePlumber](#15-audio--pipewire--wireplumber)
16. [Browser — Firefox](#16-browser--firefox)

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

> ℹ️ **LUKS recovery key:** It is strongly recommended to add a backup recovery key immediately after formatting, before you have any data to lose. Store it somewhere safe (printed, on a separate encrypted device, etc.):
> ```bash
> cryptsetup luksAddKey /dev/nvme0n1p2
> ```

### 2.5 Create Btrfs Subvolumes

```bash
mkdir /mnt/gentoo
mount /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo
btrfs subvol create {@swap,@,@home,@tmp,@cache,@repos,@log,@snapshots,@games}
cd .. && umount /mnt/gentoo
```

> ℹ️ `@games` is optional — skip it and the corresponding mount below if you don't need it.

### 2.6 Mount with Subvolume Flags

```bash
BTRFS_OPTS="compress=zstd:3,noatime,space_cache=v2,discard=async"

mount -o ${BTRFS_OPTS},subvol=@ /dev/mapper/cryptroot /mnt/gentoo
cd /mnt/gentoo

mkdir swap home .snapshots efi games
mkdir -p var/{cache,db/repos,log,tmp}

mount /dev/nvme0n1p1 /mnt/gentoo/efi
mount -o noatime,discard=async,nodatacow,subvol=@swap    /dev/mapper/cryptroot /mnt/gentoo/swap
mount -o ${BTRFS_OPTS},subvol=@home                      /dev/mapper/cryptroot /mnt/gentoo/home
mount -o ${BTRFS_OPTS},subvol=@snapshots                 /dev/mapper/cryptroot /mnt/gentoo/.snapshots
mount -o ${BTRFS_OPTS},subvol=@log                       /dev/mapper/cryptroot /mnt/gentoo/var/log
mount -o noatime,discard=async,nodatacow,subvol=@tmp     /dev/mapper/cryptroot /mnt/gentoo/var/tmp
mount -o ${BTRFS_OPTS},subvol=@cache                     /dev/mapper/cryptroot /mnt/gentoo/var/cache
mount -o ${BTRFS_OPTS},subvol=@repos                     /dev/mapper/cryptroot /mnt/gentoo/var/db/repos
mount -o ${BTRFS_OPTS},subvol=@games                     /dev/mapper/cryptroot /mnt/gentoo/games

chattr +C /mnt/gentoo/var/tmp/
chattr +C /mnt/gentoo/swap

# Create the swapfile or potentially use zram
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

### 4.1 Configure mdev.conf

mdevd uses a rules file to handle device node creation and permissions. Rather than writing one from scratch, we use the comprehensive example config maintained by the BusyBox project as a base, then append rules for DRI render nodes which it doesn't cover.

```bash
wget -O /etc/mdev.conf https://git.busybox.net/busybox/plain/examples/mdev_fat.conf
```

The BusyBox config handles the common cases well but doesn't include rules for DRI render nodes (`renderD*`), which are needed for GPU access from Wayland compositors and Vulkan. Append them after the existing video card entries:

```bash
cat << 'EOF' >> /etc/mdev.conf

# DRI render nodes — needed for Wayland compositors and Vulkan
renderD[0-9]*   root:video 660 =dri/
dri/card[0-9]*  root:video 660
dri/renderD[0-9]*   root:video 660
EOF
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

# Set musl locale
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

> 🟨 **Nvidia GPU users:** The proprietary Nvidia driver does not support musl and cannot be used on this system:
> - **NVK + Zink** — Mesa's open-source Nouveau-based Vulkan driver, with OpenGL translated through Zink. Set `VIDEO_CARDS="nouveau nvk zink"` and add `vulkan` to your USE flags. You should also accept the unstable keyword for `media-libs/mesa` — see [Section 14](#14-graphics--mesa-drivers) for instructions.
> - **Proprietary Drivers & Flatpak** — Alongside NVK and Zink you could also run games and apps in a Flatpak sandbox that bundles its own glibc-based runtime, sidestepping the musl incompatibility. You would need to install the nividia kernel modules alongside nouveau and switch between them depending on the use case - I have not yet tested this

Layer your optimised flags on top and do a full rebuild.

Before editing `make.conf`, install `cpuid2cpuflags` and run it to generate the correct `CPU_FLAGS_X86` value for your CPU. This tells Portage which instruction set extensions are available so packages can be compiled to take advantage of them:

```bash
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags
```

The output will look something like:

```
CPU_FLAGS_X86: aes avx avx2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3
```

Copy this into `make.conf` as shown below. Adjust `MAKEOPTS`, `VIDEO_CARDS`, and `USE` for your hardware.

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

MAKEOPTS="-j$(nproc)"
ACCEPT_LICENSE="*"

# Set to match your GPU
VIDEO_CARDS="amdgpu radeonsi"

# Paste the output of cpuid2cpuflags here
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

> ℹ️ `ugrd` is invoked automatically by `installkernel` after `make install` — it handles both initramfs generation and LUKS/cryptsetup integration by detecting what is currently mounted. No separate dracut or mkinitcpio step is needed.

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
UUID=<uuid>   /games         btrfs   rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@games      0 0

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
    net-misc/chrony-dinit \
    app-backup/btrbk

ln -sr /usr/lib/dinit.d/syslog-ng /usr/lib/dinit.d/boot.d/
ln -sr /usr/lib/dinit.d/fcron /usr/lib/dinit.d/boot.d/
ln -sr /usr/lib/dinit.d/chrony /usr/lib/dinit.d/boot.d/
```

fcron isn't running inside the chroot so `fcrontab` can't be used yet. Instead, drop cron fragments directly into `/etc/cron.daily/` — fcron picks these up automatically on start:

```bash
mkdir -p /etc/cron.daily

cat << 'EOF' > /etc/cron.daily/logrotate
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.conf
EOF
chmod +x /etc/cron.daily/logrotate

cat << 'EOF' > /etc/cron.daily/btrbk
#!/bin/sh
/usr/sbin/btrbk -q run
EOF
chmod +x /etc/cron.daily/btrbk
```

#### Configuring btrbk

btrbk uses a single config file at `/etc/btrbk/btrbk.conf`. The example below snapshots each subvolume daily and retains a rolling window of snapshots — adjust the retention values to taste:

```bash
mkdir -p /etc/btrbk
cat << 'EOF' > /etc/btrbk/btrbk.conf
# Snapshot directory — the @snapshots subvolume mounted at /.snapshots
snapshot_dir           /.snapshots

# Retention policy
snapshot_preserve_min  2d
snapshot_preserve      1d weekly!4

# Subvolumes to snapshot
volume /dev/mapper/cryptroot
  subvolume @
  subvolume @home
  subvolume @games
EOF
```

Retention policy breakdown:
- `snapshot_preserve_min 2d` — always keep snapshots younger than 2 days, so today's and yesterday's are guaranteed to survive regardless of other rules. This ensures you always have a clean snapshot to roll back to even if btrbk runs after a bad update on boot.
- `snapshot_preserve 1d weekly!4` — beyond the 2 day minimum, keep today's snapshot and promote one per week to a weekly slot. Exactly 4 weeklies are kept, with the oldest deleted when a 5th would be created.

> ℹ️ `@games` can be removed from the config if you didn't create that subvolume. Other subvolumes are intentionally excluded — their contents are either ephemeral or regenerable and aren't worth snapshotting.

What each package provides:
- **syslog-ng** — system logger
- **fcron** — cron daemon compatible with musl
- **logrotate** — log rotation (driven by fcron)
- **mlocate** — file index
- **bash-completion** — tab completion
- **chrony** — NTP client/server, handles time sync
- **btrbk** — btrfs snapshot and backup management, driven by fcron via cron.daily

---

## 10. Seat Management

A seat manager arbitrates access to input and graphics hardware for unprivileged Wayland compositors and display servers. Without one, starting a compositor as a regular user will fail — it cannot open DRM or input devices directly.

This guide does not use `elogind`. Instead it uses two complementary components:

- **seatd** — a minimal, standalone seat management daemon
- **turnstile** — a session/user service tracker from Chimera Linux that integrates with dinit and manages per-user service instances (including launching user-level dinit for PipeWire, WirePlumber, etc.)

Together they cover what `elogind` would otherwise provide, without pulling in large chunks of the systemd codebase.

### 10.1 Install seatd and turnstile

seatd needs the `builtin server` USE flag to enable its built-in server, which is required for unprivileged compositor startup:

```bash
echo "sys-auth/seatd builtin server" > /etc/portage/package.use/seatd
echo "sys-auth/turnstile ~amd64" > /etc/portage/package.accept_keywords/turnstile

emerge sys-auth/seatd sys-auth/turnstile
```

### 10.2 Configure turnstiled

Turnstile needs to manage the user runtime directory. Edit `/etc/turnstile/turnstiled.conf`:

```bash
sed -i 's/^manage_rundir = no/manage_rundir = yes/' /etc/turnstile/turnstiled.conf
```

### 10.3 Enable the Services

```bash
ln -sr /usr/lib/dinit.d/seatd                /usr/lib/dinit.d/boot.d/
ln -sr /etc/dinit.d/turnstiled               /usr/lib/dinit.d/boot.d/
```

### 10.4 PAM Configuration

Turnstile hooks into PAM to open and close sessions. Ensure `pam_turnstile.so` is included in your login PAM stack. Check `/etc/pam.d/login` — if it sources a common session file you may only need to add it there:

```
# /etc/pam.d/login  (or /etc/pam.d/system-login if that's what's sourced)
session  optional  pam_turnstile.so
```

> ⚠️ PAM configuration is distro-specific and the exact file to edit depends on what your profile ships. Check what exists under `/etc/pam.d/` and add the line to whichever file handles session setup for console logins.

---

## 11. Bootstrapping Rust & Java

Gentoo doesn't provide prebuilt Rust or Java packages for musl + LLVM systems. This creates a circular dependency — many packages need Rust or Java to build, but those runtimes must themselves be compiled from source.

The solution is a two-stage bootstrap: first build Rust and Java inside a temporary musl chroot that uses `libstdc++` and then change the profile to use `libcxx` (avoids the circular dependency) and produce binary packages from that chroot, then install those binaries into the main system. Once installed, they are rebuilt a second time with the main system's optimised flags.

This approach follows the [Gentoo Wiki's bootstrapping Rust via stage file](https://wiki.gentoo.org/wiki/Bootstrapping_Rust_via_stage_file).

### 11.1 Set Up the Bootstrap Chroot

```bash
emerge fakeroot
mkdir ~/gentoo-rootfs

# Update this URL to the latest musl openrc stage3 from https://www.gentoo.org/downloads/
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-musl-openrc/stage3-amd64-musl-openrc-<YYYYMMDDTHHMMSSZ>.tar.xz"
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

### 11.2 Write the Bootstrap Script

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

# Switch to the musl/llvm profile — run 'eselect profile list' to find the
# current name, as profile names change between Gentoo releases
eselect profile list
eselect profile set <N>   # select the musl/llvm profile
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

### 11.3 Run the Bootstrap

```bash
chroot ~/gentoo-rootfs /bin/bash /bootstrap.sh
```

### 11.4 Install Binary Packages into the Main System

Once the chroot script completes, copy the binary packages out and install them:

```bash
# Back up any existing binpkgs, then copy the bootstrap output
[ -d /var/cache/binpkgs ] && mv /var/cache/binpkgs /var/cache/binpkgs.bak
cp -r ~/gentoo-rootfs/var/cache/binpkgs /var/cache/binpkgs

emerge --usepkg dev-lang/rust dev-java/openjdk
```

### 11.5 Unmount the Bootstrap Chroot

Clean up the bind mounts:

```bash
umount -R ~/gentoo-rootfs/{proc,sys,dev,run}
```

### 11.6 Rebuild with Optimised Flags

Rust manages its own LTO pipeline internally via the `lto` USE flag. The `RUSTFLAGS` in `make.conf` handle linker-level LTO (passing `-Clinker-plugin-lto` to the Clang linker), while the `lto` USE flag tells Cargo to enable LTO across Rust crates. These two are complementary and should both be set, but the `no-lto.conf` env file strips the C/C++ LTO flags from the compiler environment to avoid conflicts with Rust's own pipeline:

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

## 12. User Setup & Privilege Escalation

### 12.1 Create a User Account

```bash
useradd -m -G audio,video,input,usb,wheel,seat -s /bin/bash <username>
passwd <username>
```

The group memberships match the device permissions set up in `mdev.conf` in Section 4.1:
- **audio** — access to sound devices
- **video** — access to DRI/GPU nodes
- **input** — access to keyboards, mice, and other input devices
- **usb** — access to USB devices
- **wheel** — conventionally used to gate privilege escalation (doas, sudo)
- **seat** — required for seatd access, enabling unprivileged Wayland compositor startup

### 12.2 Set Up doas

`doas` is a minimal privilege escalation tool from OpenBSD — a simpler, more auditable alternative to sudo. The `persist` USE flag must be enabled to allow authentication caching between calls.

```bash
echo "app-admin/doas persist" > /etc/portage/package.use/doas
emerge app-admin/doas
```

Create `/etc/doas.conf`:

```bash
cat << 'EOF' > /etc/doas.conf
# Allow members of the wheel group to run any command as root
# Remove 'nopass' if you want to be prompted for your password
permit persist :wheel

# Optionally allow specific passwordless commands, e.g. for power management
# permit nopass :wheel cmd poweroff
# permit nopass :wheel cmd reboot
EOF

chmod 0400 /etc/doas.conf
```

The `persist` keyword caches authentication for a short window after the first successful prompt, so you won't be asked for your password on every consecutive `doas` call.

Verify the config parses correctly:

```bash
doas -C /etc/doas.conf && echo "config ok"
```

---

## 13. Final Steps & First Boot

Exit the chroot, unmount everything, and reboot:

```bash
exit   # leave chroot

umount -R /mnt/gentoo
cryptsetup luksClose cryptroot

reboot
```

On first boot you will be prompted for your LUKS passphrase. After unlocking, log in as your user and verify the basics:

```bash
dinitctl list          # check services are running
ip link                # verify network interfaces
doas dmesg | tail -20  # check for any hardware errors
```

---

## 14. Graphics — Mesa Drivers

Mesa provides the OpenGL and Vulkan drivers for AMD, Intel, and Nvidia. Assuming `VIDEO_CARDS` has been set correctly and you are not using Nvidia, proceed with installing Mesa:

```bash
emerge media-libs/mesa
```

#### Nvidia — NVK, Zink, and the proprietary driver

The proprietary Nvidia driver is glibc-only and cannot run on musl. The open-source path is NVK + Zink:

- `nouveau` — kernel DRM driver, the foundation NVK builds on
- `nvk` — Mesa's Vulkan driver for Nouveau
- `zink` — Gallium driver that translates OpenGL to Vulkan, giving NVK OpenGL coverage

NVK and Zink are under heavy active development and the stable Gentoo tree lags significantly behind upstream. Accept the unstable keyword before emerging:

```bash
cat << 'EOF' > /etc/portage/package.accept_keywords/mesa
media-libs/mesa ~amd64
dev-libs/libclc ~amd64
media-libs/libglvnd ~amd64
EOF

emerge media-libs/mesa
```

To route all OpenGL through Zink, set this in your shell profile:

```bash
export MESA_LOADER_DRIVER_OVERRIDE=zink
```

For applications that specifically need the proprietary driver — DLSS, ray tracing, certain anti-cheat systems — Flatpak is the only viable path. Flatpak bundles its own glibc runtime, so the proprietary driver can work inside a Flatpak sandbox even on a musl host:

```bash
emerge sys-apps/flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Flatpak handles the musl incompatibility for userspace, but switching between Nouveau and the proprietary Nvidia kernel module still requires blacklisting one at boot — they cannot be loaded simultaneously. This path has not been tested and is not a supported configuration in this guide.

> ℹ️ As of 2025, NVK handles Vulkan-native titles well. OpenGL through Zink carries some overhead and occasional compatibility issues. Ray tracing and DLSS are not available. Check [Phoronix](https://www.phoronix.com) for benchmarks against your GPU generation.

---

## 15. Audio — PipeWire & WirePlumber

PipeWire requires a patch to work correctly with `libudev-zero`. Without it, PipeWire's ALSA plugin enumerates devices but then rejects them all during initialisation because `libudev-zero` does not populate the `SOUND_INITIALIZED` property that the upstream code checks for, and device parent traversal is not performed during enumeration. The patch source is tracked at [illiliti/libudev-zero#26](https://github.com/illiliti/libudev-zero/issues/26#issuecomment-2198457370) — check there for updates if the patch no longer applies cleanly against a newer PipeWire version.

Create the patch directory and drop the fix in before emerging:

```bash
mkdir -p /etc/portage/patches/media-video/pipewire
cat << 'EOF' > /etc/portage/patches/media-video/pipewire/libudev-zero-alsa-enum.patch
diff --git a/spa/plugins/alsa/alsa-udev.c b/spa/plugins/alsa/alsa-udev.c
index 9420401f0..4e0f751cf 100644
--- a/spa/plugins/alsa/alsa-udev.c
+++ b/spa/plugins/alsa/alsa-udev.c
@@ -164,9 +164,6 @@ static unsigned int get_card_nr(struct impl *this, struct udev_device *udev_devi
 	if ((str = udev_device_get_property_value(udev_device, "SOUND_CLASS")) && spa_streq(str, "modem"))
 		return SPA_ID_INVALID;
 
-	if (udev_device_get_property_value(udev_device, "SOUND_INITIALIZED") == NULL)
-		return SPA_ID_INVALID;
-
 	if ((str = udev_device_get_property_value(udev_device, "DEVPATH")) == NULL)
 		return SPA_ID_INVALID;
 
@@ -970,7 +967,7 @@ static int enum_cards(struct impl *this)
 
 	for (udev_devices = udev_enumerate_get_list_entry(enumerate); udev_devices;
 			udev_devices = udev_list_entry_get_next(udev_devices)) {
-		struct udev_device *udev_device;
+		struct udev_device *udev_device, *udev_parent_device;
 
 		udev_device = udev_device_new_from_syspath(this->udev,
 		                                           udev_list_entry_get_name(udev_devices));
@@ -979,6 +976,13 @@ static int enum_cards(struct impl *this)
 
 		process_udev_device(this, ACTION_CHANGE, udev_device);
 
+		udev_parent_device = udev_device_get_parent(udev_device);
+		if (udev_parent_device) {
+			process_udev_device(this, ACTION_CHANGE, udev_parent_device);
+		}
+
+		/* no need to call udev_device_unref(udev_parent_device) here.
+		   udev_device_unref() will free parent device implicitly */
 		udev_device_unref(udev_device);
 	}
 	udev_enumerate_unref(enumerate);
EOF
```

Portage applies any `.patch` files found under `/etc/portage/patches/<category>/<package>/` automatically at build time, so no further configuration is needed.

PipeWire is being used as the system sound server, so it needs the `sound-server` and `pipewire-alsa` USE flags:

```bash
echo "media-video/pipewire sound-server pipewire-alsa" > /etc/portage/package.use/pipewire
emerge media-video/pipewire media-video/wireplumber
```

#### User dinit service files

Turnstile starts a per-user dinit instance on login and exposes two targets that compositor and audio services can hook into:

- `graphical.target` — triggered when a graphical session is ready to start
- `graphical.monitor` — a monitor service that tracks when the graphical session is active

User services live under `~/.config/dinit.d/`. Create the directory and write the service files:

```bash
mkdir -p ~/.config/dinit.d ~/.local/state/dinit
```

D-Bus is required by PipeWire and WirePlumber. Enable the user D-Bus service by symlinking it into the user `boot.d` so it starts automatically on login:

```bash
mkdir -p ~/.config/dinit.d/boot.d
ln -sr /etc/dinit.d/user/dbus ~/.config/dinit.d/boot.d/dbus
```

**`~/.config/dinit.d/pipewire`**
```
type            = process
command         = /usr/bin/pipewire
smooth-recovery = true
logfile         = ${HOME}/.local/state/dinit/pipewire.log
depends-on      = dbus
```

**`~/.config/dinit.d/wireplumber`**
```
type            = process
command         = /usr/bin/wireplumber
smooth-recovery = true
logfile         = ${HOME}/.local/state/dinit/wireplumber.log
depends-on      = pipewire
```

For your Wayland compositor, substitute `niri` with whichever compositor you are using. The key points are that it triggers `graphical.target` on start and depends on both `graphical.monitor` and `pipewire`:

```bash
emerge gui-wm/niri   # substitute your compositor of choice
```

**`~/.config/dinit.d/niri`** (substitute your compositor)
```
type            = process
command         = bash -c "dinitctl trigger graphical.target && cd && /usr/bin/niri"
restart         = false
logfile         = ${HOME}/.local/state/dinit/niri.log
depends-on      = graphical.monitor
depends-on      = pipewire
```

Enable the services by symlinking them into the user `boot.d` directory so they start automatically on login:

```bash
cd ~/.config/dinit.d
ln -sr wireplumber boot.d/
ln -sr niri boot.d/        # substitute your compositor name
```

Verify audio is working after logging in:

```bash
wpctl status
```

---

## 16. Browser — Firefox

Before emerging Firefox, install `libatomic-stub` to prevent the build system from pulling in GCC as a dependency, and set the appropriate USE flags:

```bash
echo "www-client/firefox -telemetry system-pipewire" > /etc/portage/package.use/firefox
emerge dev-libs/libatomic-stub
emerge www-client/firefox
```
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
