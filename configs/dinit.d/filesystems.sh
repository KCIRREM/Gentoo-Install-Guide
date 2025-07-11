#!/bin/sh
export PATH=/usr/bin:/usr/sbin:/bin:/sbin


if [ "$1" != "stop" ]; then

  echo "Mounting auxillary filesystems...."
  swapon /dev/nvme0n1p2
  mount -avt noproc,nonfs
fi;
