# Gentoo-Install-Guide
An encrypted Gentoo install with btrfs and subvolumes along withe efistub as the bootloader.

UEFI conf:
  efibootmgr --create --disk /dev/nvme0n1 --label "Gentoo" --loader "\EFI\Gentoo\vmlinuz.efi" --unicode "initrd=\EFI\Gentoo\initramfs.img initrd=\EFI\Gentoo\amd-uc.img
Dracut Conf:
  add_dracutmodules+=" btrfs crypt "
kernel_cmdline+=" root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxx 
rd.luks.uuid=xxxxxxx-xxxx-xxxxx-xxxx-xxxxxxxxx rd.luks.name=xxxxx-xxxx-xxxxx-xxxxx-xxxxxxxxxx=cryptroot rootfstype=btrfs rootflags=rw,ssd,subvol=@ rd.luks.allow-discards=xxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxx "

