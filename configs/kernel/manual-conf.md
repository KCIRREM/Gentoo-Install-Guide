# Manual kernel configuaration guide
### Prerequistes
First I recommeded you go ahead and burn an ISO like mint onto a USB as we're going to need a config to grab acrively loaded modules and firmware which will only really work if we've got support builtin already.

These large distributions have to support a lot of hardware so they'll likely just work with our device out of the box, which we'll use to out advantage

When you go to boot linux mint for the first time eneter the grub config by hitting e and then append the following lines to the config,

```
dyndbg="file drivers/base/firmware_loader/main.c +fmp"
```
<sup>_Credit to this absolute hero for figuring this one out ("https://serverfault.com/questions/1026598/know-which-firmware-my-linux-kernel-has-loaded-since-booting")_</sup>

Once you've booted up chroot into your gentoo and follow the handbook - https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Kernel (the manual config part)

In case you missed it go ahead and read - https://wiki.gentoo.org/wiki/Modprobed-db, this is a useful utility to track wahts been loaded so install it and get it running.

Then use your system as you would normally to get some modules loaded into the database, try and load as many as you can -
play sound through you're speakers change the brighness

**The more you load now the easier your job will be.**
## Begin config
### Loaded Modules
```
eselect kernel list set 1
cd /usr/src/linux
make defconfig
make LSMOD=$HOME/.config/modprobed.db localmodconfig
```
Make sure to save the output of this, the various warnings and modules not found messages will be useful as it is indeed likely that the module exists it is just under a slightly different name.

Bring up the GUI
```
make nconfig
```
It sould be noted that mdev can't really automatically load firmware so we're going to need to build it all inot the kernel its probably a good idea to also turn off module support.

A typical optimisation that can be done is only enabling support for you processor

_**General setup --> Configure standard kernel features (expert users)**_ (**enable**)

_**Processor type and features --> Supported processor vendors**_ (**choose appropriate processor**)


Continue with setiing up the kernel modules, using the ouput you've saved from the kernel creation go ahead and search for all the **Warning** modules and enable them (f8 is to search) then,for all the others that were not found have a look 
and see which ones you think you might need, search for part of them and from there select the most appropriate looking option, if there isn't one just skip it.

Then just go thorugh most of the kernel up until device drivers and enable anything you think you'll need, you can always just pres h to view a 
detailed description of the currenlty selected option
### Hardware drivers
Open a new terminal and run lshw
```
lshw
```
This will output a list of all deteced hardware devices \

Then to get all of the device classes run
```
lshw -json | perl -n -e'/"class" : "(\w+)"/ && ! $seen{$1}++ && print "$1\n"'
```
Then go through each device class and look at the ouputs, 
```
lshw -c your_class
```
Go to the kernel and begin enabling what you think the right drivers are i.e \
lets say you had a 'MT7921 802.11ax PCI Express Wireless Network Adapter' you would head into 

**_Device drivers --> Network device support --> Wireless LAN --> Mediatek devices --> Mediatek MT7921E_**

### Firmware
After you've enabled all the drivers required for you're hardware were going to deal with loading the firmware blobs \
this is where enabling that earlier boot parameter will come in useful \
open a new terminal and run the following \

```
dmesg | sed -ne "s/.*Loaded FW: \(\S*\),.*/\1/p" | tr '\n' ' '
```

This should ouput a big list of firmware files, you then want to go into the kernel

**_Device Drivers --> Generic Driver Options --> Firmware loader --> Firmware loading facility --> Build named firmware blobs into the kernel binary_**

and copy the output of that command into there. 

Then just run make with the number of threads your machine has 

```
make -j8 && make modules_install && make install
```

Reboot and see if it boots, if not then take a picture of the error message reboot and re compile and try again, you could try and setup qemu howver I usually find that it only takes a couple of reboots to fix my problems.
