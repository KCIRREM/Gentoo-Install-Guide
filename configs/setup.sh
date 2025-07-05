#! /bin/bash
current_path=$(dirname $0)
mem_cap_GB=$(free -h --si | awk 'NR==2 {print $2}')
mem_cap_GB=${free_out::-1}
thread_num=$(($(($(lscpu -e=cpu | tail -1) + 1)) * 2))

if [ $mem_cap_GB -ge $(($thread_num* 2)) ]; then
  make_j=$thread_num
else
  make_j=$(($mem_cap_GB / 2))
fi
echo "MAKEOPTS=\"-j$make_j\" >> $current_path/make.conf.initial

display=$(lshw -C display)
video_cards="VIDEO_CARDS=\""
amd=false
nvidia=false
intel=false

while [[ $display =~ AMD|NVIDIA|Intel ]]; do
  if [ ${BASH_REMATCH[0]} = 'AMD' ]; then
    if [ $amd = false ]; then
      amd=true
      video_cards+=" amdgpu radeonsi"
    fi
  elif [ ${BASH_REMATCH[0]} = 'NVIDIA' ]; then
    if [ $nvidia = false ]; then
      nvidia=true
      video_cards+=" nvidia"
    fi
  else
    if [ $intel = false ]; then
      intel=true
      video_cards+=" intel"
    fi
  fi
	display="$display"
  display=${display##*"${BASH_REMATCH[0]}"}
done
echo "$video_cards \"" >> $current_path/make.conf.initial
cp $current_path/make.conf.initial /etc/portage/

emerge-webrsync
emerge app-eselect/eselect-repository
cat /usr/share/portage/config/repos.conf >> /etc/portage/repos.conf/eselect-repo.conf
eselect repository add mez-overlay git https://github.com/KCIRREM/mez-overlay.git
echo "priority = 999" >> /etc/portage/repos.conf/eselect-repo.conf
emaint sync --repo mez-overlay
eselect repository add mez-overlay git https://github.com/KCIRREM/mez-overlay.git
emerge -C sys-apps/openrc
emerge -C sys-apps/sysvinit
profile_list=$(eselect profile list | tail -n1) && [[ "$profile_list" =~ [[:digit:]]+ ]]
eselect profile set ${BASH_REMATCH[0]}
emerge --oneshot -v virtuals/service-manager
emerge --verbose --update --deep --changed-use @world
emerge --depclean
ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime
echo "en_GB ISO-8859-1" >> /etc/locale.gen 
echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set 4
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"
emerge sys-kernel/linux-firmware
emerge sys-firmware/sof-firmware
emerge sys-kernel/gentoo-sources


