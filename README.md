# Gentoo musl Guides

Opinionated guides for installing and running Gentoo Linux with a musl + LLVM/Clang toolchain.

---

## Guides

### [🐧 Install Guide](guides/gentoo-install.md)

A complete walkthrough for installing Gentoo from scratch targeting x86_64, UEFI, dinit, and a musl + LLVM/Clang toolchain. Covers disk partitioning, base system, bootstrapping Rust and Java, kernel, seat management, audio, and a Wayland desktop.

**Stack:** LUKS2 + btrfs · musl · LLVM/Clang · dinit · mdevd · turnstile

---

### [🖥️ Running Applications](guides/glibc-applications.md)

A follow-on guide covering OpenCL, Flatpak, Steam, and DaVinci Resolve on a musl system. Explains how to run glibc-linked applications without maintaining a second system, and how to expose NVK, Zink, and Rusticl to Flatpak sandboxes.

**Stack:** NVK · Zink · Rusticl · Flatpak · Steam · Proton · DaVinci Resolve

---

## Hardware Reference

The gaming guide was written and tested on:

- **CPU:** AMD with integrated Renoir GPU
- **dGPU:** NVIDIA GeForce RTX 3050 Laptop GPU (GA107, Ampere)
- **Drivers:** NVK + Zink (open source, no proprietary NVIDIA driver)
- **Mesa:** 26.x

---

## Status

> ⚠️ The musl and LLVM/Clang profiles are not officially supported by Gentoo. These guides reflect a working configuration but you may encounter packages that require patching or workarounds.

| Guide | Last verified |
|---|---|
| Install | March 2025 |
| Gaming & Applications | March 2026 |

---

## Contributing

Found an error or have an improvement? Open an issue or pull request. Please note which guide and section you are addressing, and whether you are on different hardware or a different profile configuration.
