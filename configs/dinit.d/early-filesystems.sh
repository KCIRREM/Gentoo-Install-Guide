#!/bin/sh

set -e

if [ "$1" = start ]; then

    PATH=/usr/bin:/usr/sbin:/bin:/sbin

    # Must have sysfs mounted for udevtrigger to function.
    mount -n -t sysfs sysfs /sys

    mkdir -p /dev/pts /dev/shm
    mount -n -t tmpfs -o nodev,nosuid tmpfs /dev/shm
    mount -n -t devpts -o gid=5 devpts /dev/pts

    # /run, and various directories within it
    mount -n -t tmpfs -o mode=775 tmpfs /run
    mkdir /run/lock /run/mdev

    # "hidepid=1" doesn't appear to take effect on first mount of /proc,
    # so we mount it and then remount:
    mount -n -t proc -o hidepid=1 proc /proc
    mount -n -t proc -o remount,hidepid=1 proc /proc
    ln -snf /proc/self/fd /dev/fd
    ln -snf fd/0 /dev/stdin
    ln -snf fd/1 /dev/stdout
    ln -snf fd/2 /dev/stderr

fi
