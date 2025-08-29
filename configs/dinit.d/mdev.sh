#!/bin/bash

set -e

find_mdev()
{
  if [ -x /sbin/mdev ] ; then
    echo "/sbin/mdev"
  else
    echo "/bin/busybox mdev"
  fi
}

populate_mdev()
{
  touch /dev/mdev.seq
  echo "Populating /dev with existing devices with mdev -s"
  $(find_mdev) -s
  ln -snf /proc/self/fd /dev/fd
  ln -snf fd/0 /dev/stdin
  ln -snf fd/1 /dev/stdout
  ln -snf fd/2 /dev/stderr
}

seed_dev()
{
  if [ -d /lib/mdev/devices ]; then
    cp -RFp /lib/mdev/devices* /dev 2>/dev/null
  fi
}

seed_dev
if [ -e /proc/sys/kernel/hotplug ]; then
  echo "Setting up mdev as hotplug agent"
  echo $(find_mdev) > /ptoc/sys/kernel/hotplug
fi

populate_mdev
    
      
