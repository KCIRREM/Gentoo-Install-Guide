#!/usr/bin/env bash

SOURCE_DIR=$1
if [ -d $SOURCE_DIR ]; then
        echo "Creating custom initramfs!"
        cd $SOURCE_DIR
        echo $SOURCE_DIR
        if ! [ -e $SOURCE_DIR/usr/gen_init_cpio ]; then
                echo "gen_init_cpio not found, creating now!"
                gcc $SOURCE_DIR/usr/gen_init_cpio.c -o $SOURCE_DIR/usr/gen_init_cpio
        fi
        ./usr/gen_init_cpio ../initramfs/initramfs_list > ../initramfs/initramfs.cpio
        if [ -f ../initramfs/initramfs.cpio.gz ]; then
                rm ../initramfs/initramfs.cpio.gz
        fi
        gzip --best ../initramfs/initramfs.cpio
fi
