# 🖥️ Running Applications on Gentoo musl

A follow-on guide to the [Gentoo musl Install Guide](./gentoo-install.md), covering OpenCL, Flatpak, Steam, and DaVinci Resolve on a musl + LLVM system.

> **Hardware reference:** This guide was written and tested on a system with an NVIDIA GeForce RTX 3050 Laptop GPU (GA107, Ampere) and an AMD Renoir integrated GPU, running Gentoo musl with the LLVM/Clang profile, dinit, and Mesa 26.x. The principles apply broadly but specific driver names and device indices will differ on other hardware.

> **Compositor:** Examples and notes are written for niri. The steps are compositor-agnostic — differences for other compositors are noted inline where relevant.

> **Last verified:** March 2026

---

## Table of Contents

1. [Why Flatpak on musl](#1-why-flatpak-on-musl)
2. [OpenCL — Rusticl via Zink](#2-opencl--rusticl-via-zink)
3. [Flatpak Setup](#3-flatpak-setup)
4. [Steam](#4-steam)
5. [DaVinci Resolve](#5-davinci-resolve)

---

## 1. Why Flatpak on musl

DaVinci Resolve, Steam, and most commercial Linux software are dynamically linked against glibc. They will not run natively on a musl system — glibc and musl are not ABI-compatible and no shim covers the full surface area these applications depend on.

The options are:

| Approach | Maintenance | GPU passthrough | Notes |
|---|---|---|---|
| glibc chroot | High — own Portage tree, own compiler | Manual bind mounts | Full control, brittle |
| gcompat shim | None | N/A | Only covers a subset of glibc ABI, crashes on complex apps |
| Flatpak | Low — `flatpak update` | Automatic via GL extension | Recommended |

Flatpak bundles a glibc-based runtime (`org.freedesktop.Platform`) that is downloaded once, shared between all Flatpak applications, and updated independently of your musl system. You never need a glibc compiler, a second Portage tree, or manual bind mounts. Your musl host remains uncontaminated.

The one non-trivial step is the **host GL extension** — telling Flatpak to use your system Mesa (with NVK, Zink, and Rusticl) rather than the generic Mesa it downloads from Flathub. This is a one-time setup covered in Section 3.

---

## 2. OpenCL — Rusticl via Zink

DaVinci Resolve uses OpenCL for GPU-accelerated colour grading, noise reduction, Fusion, and effects. This section sets up the OpenCL stack on the host — it is used both natively and inside Flatpak sandboxes via the host GL extension.

### 2.1 The Stack

On a musl system with NVK, OpenCL is provided by Rusticl — Mesa's OpenCL implementation — running atop the Zink Gallium driver, which in turn uses NVK for Vulkan dispatch:

```
Application → OpenCL → Rusticl → Zink (Gallium) → NVK (Vulkan) → NVIDIA GPU
                       radeonsi (Gallium) → AMD iGPU (native, no Zink needed)
```

### 2.2 Mesa USE Flags

Rusticl is built when both `llvm` and `opencl` USE flags are set on Mesa:

```bash
# /etc/portage/package.use/mesa
media-libs/mesa opencl
```

Mesa's `opencl` USE flag also pulls in Rust and `dev-util/bindgen` as build-time dependencies. Ensure `dev-lang/rust` is already installed (covered in the install guide's bootstrapping section) before rebuilding Mesa.

Rebuild Mesa:

```bash
doas emerge media-libs/mesa
```

Verify the ICD file was installed:

```bash
cat /etc/OpenCL/vendors/rusticl.icd
# should contain: libRusticlOpenCL.so.1
```

Install clinfo:

```bash
doas emerge app-misc/clinfo
```

### 2.3 Enabling Rusticl

Rusticl exposes no devices by default — each Gallium driver must be explicitly enabled via `RUSTICL_ENABLE`. The value is a **comma-separated** list (not colon-separated):

```bash
# Test
RUSTICL_ENABLE=zink,radeonsi \
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json \
  clinfo -l
```

Expected output:

```
Platform #0: rusticl
 +-- Device #0: zink Vulkan 1.4(NVIDIA GeForce RTX 3050 Laptop GPU (NVK GA107) (MESA_NVK))
 +-- Device #1: AMD Radeon Graphics (radeonsi, renoir, ACO, ...)
 `-- Device #2: zink Vulkan 1.4(NVIDIA GeForce RTX 3050 Laptop GPU (NVK GA107) (MESA_NVK))
```

**Why `VK_ICD_FILENAMES` points only to `nouveau_icd.x86_64.json`:**

Without this restriction, Zink enumerates all Vulkan devices — including the AMD GPU via RADV. This conflicts with radeonsi also trying to claim the AMD hardware, and Rusticl silently returns zero devices. Pointing `VK_ICD_FILENAMES` only at the Nouveau ICD scopes Zink exclusively to the NVIDIA GPU, leaving the AMD GPU for radeonsi's native path.

**Why three devices:**

Device #0 and #2 are the same physical GPU enumerated by the 64-bit and 32-bit Mesa multilib builds respectively. Only the 64-bit instance is used by 64-bit applications. This is harmless.

### 2.4 Persistent Configuration

```bash
# /etc/env.d/99rusticl
RUSTICL_ENABLE=zink,radeonsi
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json
```

Apply:

```bash
doas env-update && source /etc/profile
```

Verify these are in your live environment:

```bash
echo $RUSTICL_ENABLE
echo $VK_ICD_FILENAMES
clinfo -l
```

---

## 3. Flatpak Setup

### 3.1 Install Flatpak

```bash
doas emerge sys-apps/flatpak
```

Add Flathub:

```bash
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

### 3.2 Session Environment

Add to `~/.config/session/env`:

```bash
XDG_DATA_DIRS=/var/lib/flatpak/exports/share:/home/<username>/.local/share/flatpak/exports/share:/usr/local/share:/usr/share
WAYLAND_DISPLAY=wayland-1
DISPLAY=:0
XDG_CURRENT_DESKTOP=<compositor>
```

Replace `<compositor>` with the appropriate value for your compositor:

| Compositor | XDG_CURRENT_DESKTOP |
|---|---|
| niri | `niri` |
| Sway | `sway` |
| Hyprland | `Hyprland` |
| KDE Plasma | `KDE` |
| GNOME | `GNOME` |

> ℹ️ `RUSTICL_ENABLE` and `VK_ICD_FILENAMES` are already set system-wide via `/etc/env.d/99rusticl`. They do not need to be added here.

### 3.3 D-Bus Activation Environment

Flatpak portals communicate via D-Bus activation. Environment variables in your shell are not automatically visible to D-Bus-activated processes. A dinit scripted service forwards them at login.

**`~/.config/dinit.d/session-env`**
```
type        = scripted
command     = /home/<username>/.config/dinit.d/scripts/session-env
logfile     = /home/<username>/.local/state/dinit/session-env.log
depends-on  = dbus
```

**`~/.config/dinit.d/scripts/session-env`**
```bash
#!/bin/bash
dbus-update-activation-environment $(grep -v '^#' ~/.config/session/env | grep -v '^$' | xargs)
```

```bash
chmod +x ~/.config/dinit.d/scripts/session-env
ln -sr ~/.config/dinit.d/session-env ~/.config/dinit.d/boot.d/session-env
dinitctl start session-env
```

> ℹ️ **systemd users:** The equivalent is `systemctl --user import-environment` called from your compositor's startup config, or a systemd user service using `dbus-update-activation-environment --systemd`.

### 3.4 xdg-desktop-portal

Flatpak portals (file picker, URI handling, screen capture) require `xdg-desktop-portal` and a backend appropriate for your compositor. On many compositors this is pulled in as a dependency — check before installing manually:

```bash
equery d xdg-desktop-portal
```

If not present, install it along with a backend:

```bash
doas emerge sys-apps/xdg-desktop-portal
```

Common backends by compositor:

| Compositor | Backend package |
|---|---|
| niri, Sway, Hyprland | `sys-apps/xdg-desktop-portal-gtk` or `xdg-desktop-portal-wlr` |
| KDE Plasma | `sys-apps/xdg-desktop-portal-kde` |
| GNOME | `sys-apps/xdg-desktop-portal-gnome` |

> ℹ️ **niri:** xdg-desktop-portal is pulled in automatically as a dependency. No manual installation is required.

### 3.5 Host GL Extension

By default Flatpak downloads a generic Mesa build from Flathub (`org.freedesktop.Platform.GL.default`). This does not include your NVK/Zink/Rusticl configuration and will not provide OpenCL or NVK Vulkan to sandboxed applications.
However Flatpak does provide an interface for interacting with host drivers by default so we just need to enable the correct overrides.

Tell Flatpak to use the host GL driver globally for all applications:

```bash
flatpak override --user --device=dri
flatpak override --user --env=FLATPAK_GL_DRIVERS=host
```

This applies to every Flatpak you install without needing to set it per-app. If a specific application ever needs the bundled Mesa instead, override it back individually just append the app id

Verify the global override is set:

```bash
flatpak override --user --show
```

---

## 4. Steam

### 4.1 X11 Compatibility

Steam's web renderer (steamwebhelper/CEF) has a hard X11 dependency — it calls `XOpenDisplay()` directly and crashes without an X server present, regardless of Wayland availability. Patching this is not possible as steamwebhelper is a closed-source prebuilt binary.

The recommended solution is **xwayland-satellite** — install it and you are done, with no need for a separate full XWayland package or compositor-level XWayland integration:

```bash
doas emerge gui-apps/xwayland-satellite
```

xwayland-satellite is a rootless XWayland implementation that connects to your compositor's Wayland socket and presents X11 windows as normal Wayland surfaces. It is compositor-agnostic, runs as a single lightweight process, and offers better isolation than built-in compositor XWayland — X11 clients cannot see each other's input or snoop on Wayland surfaces.

> ℹ️ **niri:** Install `gui-apps/xwayland-satellite` and ensure it is in `$PATH` — niri will then manage it automatically, spawning it on-demand when an X11 client connects. No dinit service or further configuration is required.

> ℹ️ **Sway / Hyprland / compositors with built-in XWayland:** xwayland-satellite can be used instead of the compositor's built-in XWayland — disable XWayland in your compositor config and use xwayland-satellite for a single consistent approach across all X11 applications. Alternatively, leave built-in XWayland enabled and skip xwayland-satellite entirely — both work for Steam.

After installing, verify the X11 socket exists before launching Steam:

```bash
doas ss -xlp | grep X0
# should show a process holding /tmp/.X11-unix/X0
```

**Running xwayland-satellite as a dinit service (compositors without automatic management):**

If your compositor does not automatically manage xwayland-satellite, run it as a dinit user service. It requires `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` to find the compositor socket, loaded via `env-file`:

**`~/.config/dinit.d/xwayland-satellite`**
```
type        = process
command     = /usr/bin/xwayland-satellite
depends-on  = <compositor-service>
env-file    = /home/<username>/.config/session/env
logfile     = /home/<username>/.local/state/dinit/xwayland-satellite.log
```

```bash
ln -sr ~/.config/dinit.d/xwayland-satellite ~/.config/dinit.d/boot.d/xwayland-satellite
dinitctl start xwayland-satellite
```

> ⚠️ If a stale lock file from a previous crashed instance is blocking `:0`, clean it up before restarting:
> ```bash
> rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
> dinitctl restart xwayland-satellite
> ```

### 4.2 Install Steam

```bash
flatpak install --user flathub com.valvesoftware.Steam
```

Grant Steam access to your games library and set the discrete GPU:

```bash
# Games library access
flatpak override --user --filesystem=/opt/games com.valvesoftware.Steam

# Use discrete GPU (DRI_PRIME=1 selects the second GPU — adjust index if needed)
flatpak override --user --env=DRI_PRIME=1 com.valvesoftware.Steam
```

Ensure `/opt/games` is writable by your user:

```bash
doas chown <username>:<username> /opt/games
```

### 4.3 Launch Steam

```bash
flatpak run com.valvesoftware.Steam
```

On first launch Steam will perform a runtime update and migration. The following messages in the output are harmless and expected:

- `lsb_release: command not found` — Steam probes for distribution info, not present on Gentoo
- `mmap() failed: Cannot allocate memory` — CEF falling back from huge pages, non-fatal
- `Couldn't write /etc/...` — Steam's exec test probing read-only sandbox paths
- `F: X11 socket does not exist in filesystem, trying abstract socket` — the socket is abstract rather than a filesystem path, Steam finds it and continues

### 4.4 Games Library

Steam → Settings → Storage → Add Drive → `/opt/games` → three dots → **Make Default**.

### 4.5 Per-Game GPU Selection

For games that should use the discrete GPU, set the launch option in Steam → game properties → Launch Options:

```
DRI_PRIME=1 %command%
```

### 4.6 Proton

Steam uses Proton to run Windows games on Linux. Proton includes DXVK (D3D11 → Vulkan) and VKD3D-Proton (D3D12 → Vulkan), both of which work well with NVK:

```
D3D11 game → DXVK → Vulkan → NVK → RTX GPU
D3D12 game → VKD3D-Proton → Vulkan → NVK → RTX GPU
```

To enable Proton for a game: Steam → game properties → Compatibility → Force a specific Steam Play compatibility tool → select **Proton GE** (recommended) or **Proton Experimental**.

Useful launch options:

```bash
# Async shader compilation — reduces stuttering on first run
DXVK_ASYNC=1 %command%
```

### 4.7 Anti-Cheat

Most games with Easy Anti-Cheat (EAC) or BattlEye work on Linux provided the developer has enabled the Linux EAC/BattlEye runtime. Check [areweanticheatyet.com](https://areweanticheatyet.com) for per-game status before purchasing. Games marked **Denied** (e.g. Valorant, Fortnite) will not run regardless of configuration.

---

## 5. DaVinci Resolve

DaVinci Resolve is glibc-linked and requires a Flatpak or chroot to run on musl. There is no official Resolve Flatpak on Flathub — the approach below runs the official `.run` installer inside a Flatpak-managed glibc environment.

> ℹ️ This section covers the configuration principles. Community Flatpak manifests for Resolve exist and may simplify installation — search for `net.blackmagicdesign.DaVinciResolve` on GitHub for current options.

### 5.1 OpenCL Devices

With the Rusticl stack from Section 2 configured, Resolve has access to two OpenCL devices:

- **Device 0** — RTX GPU via Rusticl → Zink → NVK
- **Device 1** — AMD iGPU via Rusticl → radeonsi

In Resolve → Preferences → Memory and GPU → GPU Processing Mode, select **OpenCL** and choose the RTX GPU as the primary device.

### 5.2 Performance Expectations

| Feature | Status | Notes |
|---|---|---|
| Colour grading | ✓ Works | Via Rusticl → Zink → NVK |
| Timeline editing | ✓ Works | |
| Fusion compositor | ⚠️ Works, slower | Compute-intensive nodes slower than CUDA |
| Noise reduction | ⚠️ Works, slower | |
| Hardware video decode | ✗ Not available | Nouveau video decode not yet implemented for Ampere; CPU decode used |
| CUDA acceleration | ✗ Not available | Requires proprietary driver, incompatible with musl |
| DLSS / ray tracing | ✗ Not available | Proprietary only |

Hardware video decode via Nouveau for Ampere is under active development as part of the Nova project. CPU decode is used in the interim — performance is adequate for DCI-4K timelines on a modern CPU.

### 5.3 The cl_khr_image2d_from_buffer Extension

Resolve uses the `cl_khr_image2d_from_buffer` OpenCL extension for buffer-to-image operations in its GPU pipeline. This extension is implemented in Zink as of Mesa 26.x and provides a meaningful performance improvement over earlier Mesa versions where it was absent and Resolve fell back to slower paths.

Verify the extension is present:

```bash
RUSTICL_ENABLE=zink,radeonsi \
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json \
  clinfo 2>/dev/null | grep image2d_from_buffer
```

### 5.4 Practical Notes

- **Free version limitation** — DaVinci Resolve Free does not support multi-GPU. The Studio version is required to use both the RTX and AMD iGPU simultaneously.
- **Colour science** — OpenCL compute for colour grading at 4K and below is workable. Complex Fusion compositions or long-form noise reduction will be slower than a CUDA-capable setup — plan render times accordingly.
- **Project settings** — set GPU accelerated processing to OpenCL in project settings as well as preferences; both must match.

---

## Troubleshooting

### `clinfo -l` shows platform but no devices

The ICD loader found `rusticl.icd` but Rusticl could not initialise any driver. Check:

```bash
# Is RUSTICL_ENABLE set?
echo $RUSTICL_ENABLE

# Is the path in rusticl.icd absolute?
cat /etc/OpenCL/vendors/rusticl.icd

# Does the .so exist?
ls /usr/lib/libRusticlOpenCL.so.1

# Try bypassing the ICD loader entirely
OCL_ICD_FILENAMES=/usr/lib/libRusticlOpenCL.so.1 \
  RUSTICL_ENABLE=zink,radeonsi \
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nouveau_icd.x86_64.json \
  clinfo -l
```

### `RUSTICL_ENABLE=zink,radeonsi` shows no devices but each alone works

The conflict is Zink enumerating the AMD GPU via RADV while radeonsi also tries to claim it. Ensure `VK_ICD_FILENAMES` is set to the Nouveau ICD only — this scopes Zink to the NVIDIA GPU and prevents the conflict.

### Steam crashes with `Unable to open display`

No X11 socket is available. Check:

```bash
doas ss -xlp | grep X0
```

If empty, xwayland-satellite is not running. On niri, ensure `gui-apps/xwayland-satellite` is installed and in `$PATH`. On other compositors, start it as a dinit service as described in Section 4.1.

### xwayland-satellite fails with `NoCompositor`

xwayland-satellite cannot find the Wayland compositor socket. Ensure `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` are set correctly:

```bash
ls /run/user/1000/wayland-1   # socket should exist
echo $WAYLAND_DISPLAY          # should be wayland-1
echo $XDG_RUNTIME_DIR          # should be /run/user/1000
```

If running via a dinit service, confirm the `env-file` path is correct and contains these variables.

### xwayland-satellite fails with `server already running`

A stale lock file from a previous crashed instance is blocking `:0`. Clean it up:

```bash
dinitctl stop xwayland-satellite
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0
dinitctl start xwayland-satellite
```

### Flatpak app not using NVK / OpenCL not available inside sandbox

The host GL extension may not be set up correctly or `FLATPAK_GL_DRIVERS=host` may not be overridden for the application:

```bash
# Check global override is set
flatpak override --user --show | grep GL_DRIVERS

# Check extension directory exists and has content
ls ~/.local/share/flatpak/extension/org.freedesktop.Platform.GL.default/x86_64/

# Check libgallium symlink is not stale
ls -la ~/.local/share/flatpak/extension/org.freedesktop.Platform.GL.default/x86_64/25.08/lib/
```

---

## Resources

- [Are We Anti-Cheat Yet](https://areweanticheatyet.com) — per-game anti-cheat Linux compatibility
- [ProtonDB](https://www.protondb.com) — community reports on game compatibility with Proton
- [Mesa Rusticl documentation](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/docs/rusticl.rst)
- [NVK feature matrix](https://nouveau.freedesktop.org/FeatureMatrix.html)
- [Flatpak documentation](https://docs.flatpak.org)
- [xwayland-satellite](https://github.com/Supreeeme/xwayland-satellite)
- [niri Xwayland documentation](https://niri-wm.github.io/niri/Xwayland.html)
- [Phoronix NVK benchmarks](https://www.phoronix.com/search/NVK)
