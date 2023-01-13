Minimal Ubuntu
==============

* [Required packages](#required-packages)
* [Preparing the volume](#preparing-the-volume)
  * [Normal volume](#normal-volume)
  * [Disk image](#disk-image)
  * [EC2 volume](#ec2-volume)
* [Partitioning the volume](#partitioning-the-volume)
  * [GPT and UEFI](#gpt-and-uefi)
  * [MSDOS (for Raspberry Pi)](#msdos-for-raspberry-pi)
* [Formatting and mounting](#formatting-and-mounting)
  * [Mounting partitions for UEFI systems](#mounting-partitions-for-uefi-systems)
  * [Mounting partitions for Raspberry Pi](#mounting-partitions-for-raspberry-pi)
* [Architecture and repository URL](#architecture-and-repository-url)
  * [Ubuntu repositories](#ubuntu-repositories)
  * [AWS repositories](#aws-repositories)
* [Bootstrapping the system](#bootstrapping-the-system)
* [Minimal OS packages](#minimal-os-packages) _(TODO)_
* [Operating system installation](#operating-system-installation)
  * [User login](#user-login)
* [Kernel and helper packages](#kernel-and-helper-packages)
  * [AWS EC2 kernel](#aws-ec2-kernel)
  * [Raspberry Pi kernel](#raspberry-pi-kernel)
  * [Other systems](#other-systems)
* [Cleaning up](#cleaning-up)

Required packages
=================

To follow this document, we'll need few packages installed, namely `parted`
to partition volumes, `debootstrap` to install the base system, and `zerofree`
to clean up the volume prior to snapshotting / imaging:

```shell
apt-get update && apt-get install --yes parted debootstrap zerofree
```



Preparing the volume
====================

Regardless of what kind of system you're trying to install, we'll need an empty
volume to start the initial installation process.

Ultimately, the root volume's device needs to be set as the `BASE_DEV`
environment variable.


### Normal volume

If targeting a normal device we can simply export the `BASE_DEV` environment
variable directly:

```shell
# Simply export the root device upon which we want to install the OS
export BASE_DEV=/dev/sdb
```


### Disk image

If we want to create an image to be later written to an SD card or USB stick,
(think _Raspberry Pi_) we need to first create the image file:

```shell
# Create a simple image file, 4Gb will suffice for this install
dd if="/dev/zero" of="/raspberry-os.img" bs=4M count=1024 conv=fsync status=progress
```

Then we can use the loopback interface to use the image as a normal disk:

```shell
# Find our first available "loopback" device and use it as our BASE_DEV
BASE_DEV="$(losetup -f)"

# Associate our image file with the loopback device
losetup -P "${BASE_DEV}" "/raspberry-os.img"
```


### EC2 Volume

From the EC2 console, create a new volume (4GiB should suffice) and attach it
to a running EC2 instance where we can run the installation process.

Your mileage might vary, but simply export the device name (in most cases
`/dev/nvme1n1`) as the `BASE_DEV` environment variable.

```shell
# Simply export the root device upon which we want to install the OS
export BASE_DEV=/dev/nvme1n1
```



Partitioning the volume
=======================

We want to create two partitions on the disk: a small (256 MiB) FAT32 partition
for boot, and the rest of the as our EXT4 root volume.

We can use `parted` to simply create a basic partition layout.


### GPT and UEFI

```shell
# Create the GPT partition table
parted -s "${BASE_DEV}" mklabel gpt

# Create our two BOOT and ROOT partitions
parted -s "${BASE_DEV}" mkpart UEFI 1MiB 256MiB
parted -s "${BASE_DEV}" mkpart ROOT 256MiB 100%

# Setup flags on our UEFI partition
parted -s "${BASE_DEV}" set 1 boot on
parted -s "${BASE_DEV}" set 1 esp on
```


### MSDOS (for Raspberry Pi)

```shell
# Create the MSDOS partition table
parted -s "${BASE_DEV}" mklabel msdos

# Create our two BOOT and ROOT partitions
parted -s "${BASE_DEV}" mkpart primary fat32 1MiB 256MiB
parted -s "${BASE_DEV}" mkpart primary ext4 256MiB 100%

# Set the boot partition as bootable
parted -s "${BASE_DEV}" set 1 boot on
```



Formatting and mounting
=======================

Take quick break, sometimes it takes a second or two for the kernel to populate
the device tree... Then let's figure out the partitions UUIDs and devices:

```shell
# Find the UUID and device of the boot partition
export BOOT_UUID="$(partx -go UUID -n 1 "${BASE_DEV}")"
export BOOT_DEV="$(realpath /dev/disk/by-partuuid/"${BOOT_UUID}")"

# Find the UUID and device of the root partition
export ROOT_UUID="$(partx -go UUID -n 2 "${BASE_DEV}")"
export ROOT_DEV="$(realpath /dev/disk/by-partuuid/"${ROOT_UUID}")"
```

Then create our file systems:

```shell
mkfs.fat -F32 "${BOOT_DEV}"
mkfs.ext4 -F "${ROOT_DEV}"
```


### Mounting partitions for UEFI systems

We'll mount the root partition under `/mnt` and for UEFI systems, the boot
partition will be mounted under `/mnt/boot/efi`:

```shell
mount "${ROOT_DEV}" /mnt
mkdir -p /mnt/boot/efi
mount  "${BOOT_DEV}" /mnt/boot/efi
```


### Mounting partitions for Raspberry Pi

We'll mount the root partition under `/mnt` and for the Raspberry Pi, the
mountpoints of our boot partition is `/mnt/boot/rpi`::

```shell
mount "${ROOT_DEV}" /mnt
mkdir -p /mnt/boot/rpi
mount  "${BOOT_DEV}" /mnt/boot/rpi
```



Minimal OS packages
===================

> TODO: we need to set up our APT repo to download the packages
>
> ```shell
> curl -L -o '/mnt/minimal-os-setup.deb' \
>   'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.4/minimal-os-setup_1.0.4_all.deb'
> curl -L -o '/mnt/minimal-os.deb' \
>   'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.4/minimal-os_1.0.4_all.deb'
> curl -L -o '/mnt/minimal-ec2-os.deb' \
>  'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.4/minimal-ec2-os_1.0.4_all.deb'
> curl -L -o '/mnt/minimal-rpo-os.deb' \
>  'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.4/minimal-rpi-os_1.0.4_all.deb'
> ```



Architecture and repository URL
===============================

To bootstrap the system, we need to find the correct URL of the Ubuntu
repository we want to fetch our packages from, and the architecture of the
system we are trying to install.

We export this into the `REPO_URL` and `TARGET_ARCH` environment variables.

Remember, Raspberry Pis, AWS Graviton instances, M1/M2 Macs are ARM64!

### Ubuntu repositories

Normally we want to use a local mirror of the Ubuntu repositories, in our case
we're in Germany, so we'll use the `de` mirrors.

In our case, for `ARM64`, the repository base URL will be:

```shell
export REPO_URL="http://de.ports.ubuntu.com/ubuntu-ports"
export TARGET_ARCH="arm64"
```

While for `X86_64` the repository base URL will be:

```shell
export REPO_URL="http://de.archive.ubuntu.com/ubuntu"
export TARGET_ARCH="amd64"
```

### AWS repositories

AWS provides mirrors of the various Ubuntu repositories per region, so we can
use those for speed. We can get the region calling:

```shell
export AWS_REGION="$(curl --silent http://169.254.169.254/latest/meta-data/placement/region)"
```

Then for `ARM64` the repository base URL will be:

```shell
export REPO_URL="http://${AWS_REGION}.clouds.ports.ubuntu.com/ubuntu-ports"
export TARGET_ARCH="arm64"
```

While for `X86_64` the repository base URL will be:

```shell
export REPO_URL="http://${AWS_REGION}.clouds.archive.ubuntu.com/ubuntu"
export TARGET_ARCH="amd64"
```



Bootstrapping the system
========================

Now we can simply use `debootstrap` to install the basics of the OS:

```shell
debootstrap --arch="${TARGET_ARCH}" --variant=minbase --include=systemd jammy /mnt "${REPO_URL}"
```

Once `debootstrap` is finished, we can mount the various filesystems required by
the installation:

```shell
mount -t proc proc "/mnt/proc"
mount -t sysfs sysfs "/mnt/sys"
mount -o bind /run "/mnt/run"
mount -o bind /dev "/mnt/dev"
mount -o bind /dev/pts "/mnt/dev/pts"
```

And then `chroot` into our new environment using the `C` locale (as no other
locale has yet been generated):

```shell
eval $(LANG=C LC_ALL=C LANGUAGE=C locale) chroot "/mnt" /bin/bash --login
bind 'set enable-bracketed-paste off'
```



Operating system installation
=============================

We continue the installation by configuring some basic files.

First of all, we need to prepare the `/etc/hostname` and `/etc/hosts` files:

```shell
# Set the generic "ubuntu" host name
echo "ubuntu" > "/etc/hostname"

# Basic "hosts" file for "ubuntu"
cat > "/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 ubuntu ubuntu.local
EOF
```

Then we'll set up the `/etc/mtab` link and `/etc/fstab` file:

```shell
ln -sf "/proc/self/mounts" "/etc/mtab"

cat > "/etc/fstab" << EOF
$(printf "# %-41s %-15s %-5s %-17s %-5s %s" "PARTITION" "MOUNTPOINT" "TYPE" "OPTIONS" "DUMP" "FSCK")
$(printf "UUID=%-38s %-15s %-5s %-17s %-5s %s" $(findmnt -no UUID,TARGET,FSTYPE "${ROOT_DEV}") "defaults,discard" "0" "1")
$(printf "UUID=%-38s %-15s %-5s %-17s %-5s %s" $(findmnt -no UUID,TARGET,FSTYPE "${BOOT_DEV}") "umask=0077" "0" "1")
EOF
```

We then need to prepare our sources list for APT in `/etc/apt/sources.list`:

```shell
cat > "/etc/apt/sources.list" << EOF
deb ${REPO_URL} jammy main restricted universe multiverse
deb ${REPO_URL} jammy-updates main restricted universe multiverse
deb ${REPO_URL} jammy-security main restricted universe multiverse
EOF
```

We then want to update the system, and install all packages required for a
minimal system.

The `minimal-os` package provided here is a meta-package that requires only
a minimal set of dependencies, and provides some basic system configuration.

```shell
export DEBIAN_FRONTEND=noninteractive

export APT_OPTIONS="\
  -oAPT::Install-Recommends=false \
  -oAPT::Install-Suggests=false \
  -oAcquire::Languages=none"

apt-get $APT_OPTIONS update && \
  apt-get $APT_OPTIONS --yes dist-upgrade && \
  apt-get $APT_OPTIONS --yes install /minimal-os-setup.deb /minimal-os.deb
```

Then for sanity's sake, let's keep only the `minimal-os` package marked as
_manually installed_ (this will help with `apt-get autoremove`):

```shell
apt-mark showmanual | xargs apt-mark auto
apt-mark manual minimal-os
```


### User login

The `minimal-os` package installs the `ubuntu` user by default. If you need
to log in interactively (e.g. from the console) set the password now:

```shell
passwd ubuntu
```

If you need SSH access, we only allow SSH keys. Place the authorized SSH public
key in `/home/ubuntu/.ssh/authorized_keys`.

Finally, we allow **password-less sudo** for the `ubuntu` user. If this is not
to your liking, take a peek at the `/etc/sudoers.d/00-minimal-os` file.



Kernel and helper packages
==========================

Next step is to install a kernel and our helper package for AWS EC2 or Raspberry
Pi systems.

### AWS EC2 kernel

For AWS EC2 instances, the `minimal-ec2-os` package will install `grub` and its
configurations on the root device. The kernel comes from `linux-aws`:

```shell
apt-get --yes install linux-aws /minimal-ec2-os.deb
```

### Raspberry Pi kernel

For the Raspberry Pi, we don't need a boot loader, and the `minimal-rpi-os` will
take care of preparing the `/boot/rpi` filesystem for booting:

```shell
apt-get --yes install linux-raspi /minimal-rpi-os.deb
```

### Other systems

For all other systems the `linux-generic` kernel is a good starting point:

```shell
apt-get --yes install linux-generic grub-efi
```

We then need to configure the `grub` boot loader, as a starting point use:

```shell
# Basic minimal GRUB configuration
cat > "/etc/default/grub" << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE="hidden"
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset console=tty1"
GRUB_DISTRIBUTOR="Minimal Ubuntu OS"
EOF

# Install GRUB on the boot device, and update the kernel
grub-install "${BASE_DEV}"
update-grub
```



Cleaning up
===========

Let's clean up our APT state and exit the chrooted environment:

```shell
apt-get clean && exit
```

We then want to clean up a bunch of files left over by the installation, some
of them will be re-created once `minimal-ec2-os-setup` runs the first time:

```shell
rm -f /mnt/minimal*os.deb \
      /mnt/etc/ssh/ssh_host_*_key* \
      /mnt/root/.bash_history \
      /mnt/var/log/alternatives.log \
      /mnt/var/log/apt/* \
      /mnt/var/log/bootstrap.log \
      /mnt/var/log/dpkg.log
```

At this point we can simply unmount our volume:

```shell
umount -Rlf /mnt
```


Creating an AMI
---------------

First of all clean out any unused block in our root filesystem:

```shell
zerofree -v "${ROOT_DEV}"
```

Going back to the EC2 console we can now detach the volume we created from the
EC2 instance we used for setup, and create a snapshot from it.

Once the snapshot is created, we can then create an image from it (remember,
select the snapshot then _Actions -> Create image from snapshot_, it is **not**
in the _AMI_ section of the console).

Remember to select the following:
* _Architecture_: either `arm64` or `x86_64`
* _Root device name_: always `/dev/sda1`
* _Virtualization type_: always `Hardware-assisted virtualization`
* _Boot mode_: always `UEFI`
