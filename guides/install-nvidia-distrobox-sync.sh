#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31m[ERROR] This setup script must be run as root (or with sudo/doas).\e[0m"
  exit 1
fi

INITIAL_NVIDIA_EBUILD_URL="https://raw.githubusercontent.com/KCIRREM/Gentoo-Install-Guide/refs/heads/main/guides/nvidia-initial.ebuild"
NVIDIA_DISTROBOX_SYNC_HOOK_URL="https://raw.githubusercontent.com/KCIRREM/Gentoo-Install-Guide/refs/heads/main/guides/nvidia-distrobox-sync"

REPO="local"
CATEGORY="sys-kernel"
PACKAGE="nvidia-drivers"

NORMAL_USER="${SUDO_USER:-$USER}"
CONTAINER="fedora"

CONF_FILE="/etc/distrobox-nvidia-sync.conf"

OVERLAY="/var/db/repos/${REPO}"
PACKAGE_DIR="${CATEGORY}/${PACKAGE}"

echo -e "\e[36m>>> Setting up Local Portage Repository...\e[0m"
eselect repository create "$REPO" || true
mkdir -p "$OVERLAY/$PACKAGE_DIR"

echo -e "\e[36m>>> Writing config...\e[0m"
# Write all variables cleanly in one pass
cat > "$CONF_FILE" <<EOF
REPO="$REPO"
CATEGORY="$CATEGORY"
PACKAGE="$PACKAGE"
NORMAL_USER="$NORMAL_USER"
CONTAINER="$CONTAINER"
OVERLAY="/var/db/repos/$REPO"
PACKAGE_DIR="$CATEGORY/$PACKAGE"
FEDORA_VER=
EOF

echo -e "\e[36m>>> Fetching Nvidia DistroBox sync hook...\e[0m"
mkdir -p /etc/portage/postsync.d
HOOK="/etc/portage/postsync.d/nvidia-distrobox-sync"

wget -qO "$HOOK" "$NVIDIA_DISTROBOX_SYNC_HOOK_URL"

# Safely inject config path
sed -i "0,/^CONF_FILE=/s//CONF_FILE=\"${CONF_FILE//\//\\/}\"/" "$HOOK"
chmod +x "$HOOK"

echo -e "\e[36m>>> Fetching and Manifesting Initial Ebuild...\e[0m"
wget -qO "/tmp/nvidia-initial.ebuild" "$INITIAL_NVIDIA_EBUILD_URL"

EBUILD_VER=$(grep -PoE -m 1 'Current Version \K.*' "/tmp/nvidia-initial.ebuild")

if [ -z "$EBUILD_VER" ]; then
    echo -e "\e[31m[ERROR] Could not extract version.\e[0m"
    exit 1
fi

TARGET_EBUILD="$OVERLAY/$PACKAGE_DIR/$PACKAGE-${EBUILD_VER}.ebuild"
mv "/tmp/nvidia-initial.ebuild" "$TARGET_EBUILD"
ebuild "$TARGET_EBUILD" manifest

echo -e "\e[36m>>> Generating Portage Hook For $PACKAGE...\e[0m"
mkdir -p "/etc/portage/env/$CATEGORY/"

cat << EOF > "/etc/portage/env/$PACKAGE_DIR"
pkg_postinst() {
    source "$CONF_FILE"
EOF

cat << 'EOF' >> "/etc/portage/env/$PACKAGE_DIR"
    su -c "distrobox-enter -n $CONTAINER -- sudo dnf versionlock delete xorg-x11-drv-nvidia\* nvidia-driver-cuda\* || true" "$NORMAL_USER"
    su -c "distrobox-enter -n $CONTAINER -- sudo dnf install --allowerasing -y xorg-x11-drv-nvidia-$FEDORA_VER nvidia-driver-cuda-$FEDORA_VER" "$NORMAL_USER"
    su -c "distrobox-enter -n $CONTAINER -- sudo dnf versionlock add --raw '*xorg-x11-drv-nvidia-*$FEDORA_VER*' '*nvidia-driver-cuda-*$FEDORA_VER*'" "$NORMAL_USER"
}
EOF

echo -e "\e[36m>>> Provisioning Fedora Distrobox Container...\e[0m"
su -c "distrobox create --image registry.fedoraproject.org/fedora:latest --name $CONTAINER -Y" "$NORMAL_USER"

# Fixed the cut-off URL here
su -c "distrobox-enter -n $CONTAINER -- sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm" "$NORMAL_USER"

su -c "distrobox-enter -n $CONTAINER -- sudo dnf update -y" "$NORMAL_USER"

# Required to make the portage env hook work
su -c "distrobox-enter -n $CONTAINER -- sudo dnf install -y xorg-x11-drv-nvidia xorg-x11-drv-nvidia-libs.i686 xorg-x11-drv-nvidia-cuda python3-dnf-plugin-versionlock" "$NORMAL_USER"

echo -e "\e[32m>>> Setup Complete! System is ready for hybrid sync.\e[0m"
echo -e "\e[32m>>> Run emaint sync && emerge ${PACKAGE_DIR} to start sync.\e[0m"
