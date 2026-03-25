# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop dot-a eapi9-pipestatus eapi9-ver flag-o-matic linux-mod-r1
inherit readme.gentoo-r1 systemd toolchain-funcs unpacker user-info

MODULES_KERNEL_MAX=6.19
NV_URI="https://download.nvidia.com/XFree86/"

DESCRIPTION="NVIDIA Accelerated Graphics Driver"
HOMEPAGE="https://www.nvidia.com/"
SRC_URI="
	amd64? ( ${NV_URI}Linux-x86_64/${PV}/NVIDIA-Linux-x86_64-${PV}.run )
        arm64? ( ${NV_URI}Linux-aarch64/${PV}/NVIDIA-Linux-aarch64-${PV}.run )
        $(printf "${NV_URI}%s/%s-${PV}.tar.bz2 " \
                nvidia-{installer,modprobe,persistenced,settings,xconfig}{,})
	${NV_URI}NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-${PV}.tar.xz
"
# nvidia-installer is unused but here for GPL-2's "distribute sources"
S=${WORKDIR}

LICENSE="
	NVIDIA-2025 Apache-2.0 Boost-1.0 BSD BSD-2 GPL-2 MIT ZLIB
	curl openssl public-domain
"
SLOT="0/${PV%%.*}"
KEYWORDS="-* amd64 ~arm64"
IUSE="
        abi_x86_32 abi_x86_64 +kernel-open
"
# there is some non-prebuilt exceptions but rather not maintain a list
QA_PREBUILT="lib/firmware/* usr/bin/* usr/lib*"

pkg_setup() {
	[[ ${MERGE_TYPE} != binary ]] || return

	# do early before linux-mod-r1 so can use chkconfig to setup CONFIG_CHECK
	get_version
	require_configured_kernel

	local CONFIG_CHECK="
		PROC_FS
		~DRM_KMS_HELPER
		~DRM_FBDEV_EMULATION
		~SYSVIPC
		~!LOCKDEP
		~!PREEMPT_RT
		~!RANDSTRUCT_FULL
		~!RANDSTRUCT_PERFORMANCE
		~!SLUB_DEBUG_ON
		!DEBUG_MUTEXES
	"

	kernel_is -ge 6 11 && linux_chkconfig_present DRM_FBDEV_EMULATION &&
		CONFIG_CHECK+=" DRM_TTM_HELPER"

	use amd64 && kernel_is -ge 5 8 && CONFIG_CHECK+=" X86_PAT" #817764

	use kernel-open && CONFIG_CHECK+=" MMU_NOTIFIER" #843827

	local drm_helper_msg="Cannot be directly selected in the kernel's config menus, and may need
	selection of a DRM device even if unused, e.g. CONFIG_DRM_QXL=m or
	DRM_AMDGPU=m (among others, consult the kernel config's help), can
	also use DRM_NOUVEAU=m as long as built as module *not* built-in."
	local ERROR_DRM_KMS_HELPER="CONFIG_DRM_KMS_HELPER: is not set but is needed for nvidia-drm.modeset=1
	support (see ${EPREFIX}/etc/modprobe.d/nvidia.conf) which is needed for wayland
	and for config-less Xorg auto-detection.
	${drm_helper_msg}"
	local ERROR_DRM_TTM_HELPER="CONFIG_DRM_TTM_HELPER: is not set but is needed to compile when using
	kernel version 6.11.x or newer while DRM_FBDEV_EMULATION is set.
	${drm_helper_msg}"
	local ERROR_DRM_FBDEV_EMULATION="CONFIG_DRM_FBDEV_EMULATION: is not set but is needed for
	nvidia-drm.fbdev=1 support (see ${EPREFIX}/etc/modprobe.d/nvidia.conf), may
	result in a blank console/tty."
	local ERROR_MMU_NOTIFIER="CONFIG_MMU_NOTIFIER: is not set but needed to build with USE=kernel-open.
	Cannot be directly selected in the kernel's menuconfig, and may need
	selection of another option that requires it such as CONFIG_AMD_IOMMU=y,
	or DRM_I915=m (among others, consult the kernel config's help)."
	local ERROR_PREEMPT_RT="CONFIG_PREEMPT_RT: is set but is unsupported by NVIDIA upstream and
	will fail to build unless the env var IGNORE_PREEMPT_RT_PRESENCE=1 is
	set. Please do not report issues if run into e.g. kernel panics while
	ignoring this."
	local randstruct_msg="is set but NVIDIA may be unstable with
	it such as causing a kernel panic on shutdown, it is recommended to
	disable with CONFIG_RANDSTRUCT_NONE=y (https://bugs.gentoo.org/969413
	-- please report if this appears fixed on NVIDIA's side so can remove
	this warning)."
	local ERROR_RANDSTRUCT_FULL="CONFIG_RANDSTRUCT_FULL: ${randstruct_msg}"
	local ERROR_RANDSTRUCT_PERFORMANCE="CONFIG_RANDSTRUCT_PERFORMANCE: ${randstruct_msg}"

	linux-mod-r1_pkg_setup
}

src_prepare() {
	# make patches usable across versions
	rm nvidia-modprobe && mv nvidia-modprobe{-${PV},} || die
	rm nvidia-settings && mv nvidia-settings{-${PV},} || die
	rm nvidia-xconfig && mv nvidia-xconfig{-${PV},} || die
	mv NVIDIA-kernel-module-source-${PV} kernel-module-source || die

	default

	# prevent detection of incomplete kernel DRM support (bug #603818)
	sed 's/defined(CONFIG_DRM/defined(CONFIG_DRM_KMS_HELPER/g' \
		-i kernel{,-module-source/kernel-open}/conftest.sh || die
}

src_compile() {
	tc-export AR CC CXX LD OBJCOPY OBJDUMP PKG_CONFIG

	NV_ARGS=(
                PREFIX="${EPREFIX}"/usr
                HOST_CC="$(tc-getBUILD_CC)"
                HOST_LD="$(tc-getBUILD_LD)"
                NV_VERBOSE=1 DO_STRIP= MANPAGE_GZIP= OUTPUTDIR=out
                TARGET_ARCH="${target_arch}"
        )

	# extra flags for the libXNVCtrl.a static library

	# Same as uname -m.
	local target_arch
	case ${ARCH} in
		amd64) target_arch=x86_64 ;;
		arm64) target_arch=aarch64 ;;
		*) die "Unrecognised architecture: ${ARCH}" ;;
	esac

	local o_cflags=${CFLAGS} o_cxxflags=${CXXFLAGS} o_ldflags=${LDFLAGS}

	local modlistargs=video:kernel
	if use kernel-open; then
		modlistargs+=-module-source:kernel-module-source/kernel-open

		# environment flags are normally unused for modules, but nvidia
		# uses it for building the "blob" and it is a bit fragile
		filter-flags -fno-plt #912949
		filter-lto
		CC=${KERNEL_CC} CXX=${KERNEL_CXX} strip-unsupported-flags
		LDFLAGS=$(raw-ldflags)
	fi

	local modlist=( nvidia{,-drm,-modeset,-peermem,-uvm}=${modlistargs} )
	local modargs=(
		IGNORE_CC_MISMATCH=yes NV_VERBOSE=1
		SYSOUT="${KV_OUT_DIR}" SYSSRC="${KV_DIR}"
		TARGET_ARCH="${target_arch}"

		# kernel takes "x86" and "x86_64" as meaning the same, but nvidia
		# makes the distinction (since 550.135) and is not happy with "x86"
		# TODO?: it should be ok/better for tc-arch-kernel to do x86_64
		$(usev amd64 ARCH=x86_64)
	)

	# temporary workaround for bug #914468
	addpredict "${KV_OUT_DIR}"

	linux-mod-r1_src_compile
	CFLAGS=${o_cflags} CXXFLAGS=${o_cxxflags} LDFLAGS=${o_ldflags}

}

src_install() {
	local libdir=$(get_libdir) libdir32=$(ABI=x86 get_libdir)

	local skip_types=(
		GLVND_LIB GLVND_SYMLINK EGL_CLIENT.* GLX_CLIENT.*
		OPENCL_WRAPPER.* DOCUMENTATION DOT_DESKTOP .*_SRC
		DKMS_CONF SYSTEMD_UNIT .*_BINARY .*_LIB .*_SYMLINK
	)

	NV_ARGS+=( DESTDIR="${D}" LIBDIR="${ED}"/usr/${libdir} )

	local -A paths=(
		[FIRMWARE]=/lib/firmware/nvidia/${PV}
	)

	local DOC_CONTENTS="\
		Trusted users should be in the 'video' group to use NVIDIA devices.
		You can add yourself by using: gpasswd -a my-user video

		Like all out-of-tree kernel modules, it is necessary to rebuild
		${PN} after upgrading or rebuilding the Linux kernel
		by for example running \`emerge @module-rebuild\`. Alternatively,
		if using a distribution kernel (sys-kernel/gentoo-kernel{,-bin}),
		this can be automated by setting USE=dist-kernel globally.

		Loaded kernel modules also must not mismatch with the installed
		${PN} version (excluding -r revision), meaning should
		ensure \`eselect kernel list\` points to the kernel that will be
		booted before building and preferably reboot after upgrading
		${PN} (the ebuild will emit a warning if mismatching).

		See '${EPREFIX}/etc/modprobe.d/nvidia.conf' for modules options.\
		$(use amd64 && usev !abi_x86_32 "

		Note that without USE=abi_x86_32 on ${PN}, 32bit applications
		(typically using wine / steam) will not be able to use GPU acceleration.")

		Be warned that USE=kernel-open may need to be either enabled or
		disabled for certain cards to function:
			- GTX 50xx (blackwell) and higher require it to be enabled
			- GTX 1650 and higher (pre-blackwell) should work either way
			- Older cards require it to be disabled

		For additional information or for troubleshooting issues, please see
		https://wiki.gentoo.org/wiki/NVIDIA/nvidia-drivers and NVIDIA's own
		documentation that is installed alongside this README."

	readme.gentoo_create_doc

	linux-mod-r1_src_install

	insinto /etc/modprobe.d
	newins "${FILESDIR}"/nvidia-580.conf nvidia.conf

	# used for gpu verification with binpkgs (not kept, see pkg_preinst)
	insinto /usr/share/nvidia
	doins supported-gpus/supported-gpus.json


	local m into
	while IFS=' ' read -ra m; do
		[[ ${m[2]} != FIRMWARE* && ${m[2]} != EXPLICIT_PATH ]] && continue

		einfo "Foud ${m} installing -------------------------------------"
	        if [[ -v "paths[${m[2]}]" ]]; then
			into=${paths[${m[2]}]}
		elif [[ ${m[2]} == EXPLICIT_PATH ]]; then
			[[ ${m[3]} != /lib/firmware* ]] && continue
			into=${m[3]}
		else
			die "No known installation path for ${m[0]} (Type: ${m[2]})"
		fi

		[[ ${m[3]: -2} == ?/ ]] && into+=/${m[3]%/}
		[[ ${m[4]: -2} == ?/ ]] && into+=/${m[4]%/}

		if [[ ${m[2]} =~ _SYMLINK$ ]]; then
			[[ ${m[4]: -1} == / ]] && m[4]=${m[5]}
			dosym ${m[4]} ${into}/${m[0]}
			continue
		fi

	        printf -v m[1] %o $((m[1] | 0200))
		insopts -m${m[1]}
		insinto ${into}
		doins ${m[0]}

	done < .manifest || die


	insopts -m0644 # reset

	# MODULE:installer non-skipped extras
	# don't attempt to strip firmware files (silences errors)
	dostrip -x ${paths[FIRMWARE]}


	# our settings are used for bug 932781#c8 and nouveau blacklist if either
	# modules are included (however, just best-effort without initramfs regen)
	echo "install_items+=\" ${EPREFIX}/etc/modprobe.d/nvidia.conf \"" >> \
		"${ED}"/usr/lib/dracut/dracut.conf.d/10-${PN}.conf || die
}

pkg_preinst() {
	has_version "${CATEGORY}/${PN}[kernel-open]" && NV_HAD_KERNEL_OPEN=

        # set video group id based on live system (bug #491414)
        local g=$(egetent group video | cut -d: -f3)
        [[ ${g} =~ ^[0-9]+$ ]] || die "Failed to determine video group id (got '${g}')"
        sed -i "s/@VIDEOGID@/${g}/" "${ED}"/etc/modprobe.d/nvidia.conf || die

        # try to find driver mismatches using temporary supported-gpus.json
        for g in $(grep -l 0x10de /sys/bus/pci/devices/*/vendor 2>/dev/null); do
                g=$(grep -io "\"devid\":\"$(<${g%vendor}device)\"[^}]*branch\":\"[0-9]*" \
                        "${ED}"/usr/share/nvidia/supported-gpus.json 2>/dev/null)
                if [[ ${g} ]]; then
                        g=$((${g##*\"}+1))
                        if ver_test -ge ${g}; then
                                NV_LEGACY_MASK=">=${CATEGORY}/${PN}-${g}"
                                break
                        fi
                fi
        done
        rm "${ED}"/usr/share/nvidia/supported-gpus.json || die

}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	readme.gentoo_print_elog

	if [[ -r /proc/driver/nvidia/version &&
		$(</proc/driver/nvidia/version) != *"  ${PV}  "* ]]; then
		ewarn "\nCurrently loaded NVIDIA modules do not match the newly installed"
		ewarn "libraries and may prevent launching GPU-accelerated applications."
		ewarn "Easiest way to fix this is normally to reboot. If still run into issues"
		ewarn "(e.g. API mismatch messages in the \`dmesg\` output), please verify"
		ewarn "that the running kernel is ${KV_FULL} and that (if used) the"
		ewarn "initramfs does not include NVIDIA modules (or at least, not old ones)."
	fi

	if [[ $(</proc/cmdline) == *slub_debug=[!-]* ]]; then
		ewarn "\nDetected that the current kernel command line is using 'slub_debug=',"
		ewarn "this may lead to system instability/freezes with this version of"
		ewarn "${PN}. Bug: https://bugs.gentoo.org/796329"
	fi

	if [[ -v NV_LEGACY_MASK ]]; then
		ewarn "\n***WARNING***"
		ewarn "\nYou are installing a version of ${PN} known not to work"
		ewarn "with a GPU of the current system. If unwanted, add the mask:"
		if [[ -d ${EROOT}/etc/portage/package.mask ]]; then
			ewarn "  echo '${NV_LEGACY_MASK}' > ${EROOT}/etc/portage/package.mask/${PN}"
		else
			ewarn "  echo '${NV_LEGACY_MASK}' >> ${EROOT}/etc/portage/package.mask"
		fi
		ewarn "...then downgrade to a legacy[1] branch if possible (not all old versions"
		ewarn "are available or fully functional, may need to consider nouveau[2])."
		ewarn "[1] https://www.nvidia.com/object/IO_32667.html"
		ewarn "[2] https://wiki.gentoo.org/wiki/Nouveau"
	fi

	if use kernel-open && [[ ! -v NV_HAD_KERNEL_OPEN ]]; then
		ewarn "\nOpen source variant of ${PN} was selected, note that it requires"
		ewarn "Turing/Ampere+ GPUs (aka GTX 1650+). Try disabling if run into issues."
		ewarn "Also see: ${EROOT}/usr/share/doc/${PF}/html/kernel_open.html"
	fi

	if ver_replacing -lt 580.126.09-r1; then
		elog "\n>=nvidia-drivers-580.126.09-r1 changes some defaults that may or may"
		elog "not need attention:"
		elog "1. nvidia-drm.modeset=1 is now default regardless of USE=wayland"
		elog "2. nvidia-drm.fbdev=1 is now also tentatively default to match upstream"
		elog "See ${EROOT}/etc/modprobe.d/nvidia.conf to modify settings if needed,"
		elog "fbdev=1 *could* cause issues for the console display with some setups."
	fi
}
