Creating a minimal Ubuntu AMI
=============================

Preparing the volume
--------------------

From the EC2 console, create a new volume (2GiB should suffice) and attach it
to a running EC2 instance where we can run the installation process.

We want to create a single (bootable) partition on the disk encompassing the
entire volume formatted as `ext4`.

If you have `parted` installed (or just copy-and-paste below), you can simply
create a basic layout as follows:

```
apt-get install --yes parted
parted -s /dev/xvdf mklabel msdos
parted -s /dev/xvdf mkpart primary ext4 2048s 100%
parted -s /dev/xvdf set 1 boot on
sync
mkfs.ext4 /dev/xvdf1
```

Otherwise your mileage will vary. Just make sure to `mount` your partition
under `/mnt`:

```
mount /dev/xvdf1 /mnt
```

Bootstrapping the system
------------------------

First let's get our region:

```
REGION="$(curl --silent http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -E 's|[a-z]+$||g')"
```

We'll use `debootstrap` to bootstrap a `minbase` system into `/mnt`:

```
apt-get install --yes debootstrap
debootstrap --arch=amd64 --variant=minbase --exclude=makedev \
  bionic /mnt http://${REGION}.ec2.archive.ubuntu.com/ubuntu/
```

First we'll set up the `/etc/mtab` link and `/etc/fstab` file:

```
ln -sf /proc/self/mounts /mnt/etc/mtab

FMT="%-42s %-11s %-5s %-9s %-5s %s"
cat > "/mnt/etc/fstab" << EOF
$(printf "${FMT}" "# DEVICE UUID" "MOUNTPOINT" "TYPE" "OPTIONS" "DUMP" "FSCK")
$(findmnt -no SOURCE /mnt | xargs blkid -o export | awk -v FMT="${FMT}" '/^UUID=/ { printf(FMT, $0, "/", "ext4", "defaults", "0", "1" ) }')
EOF
unset FMT
```

We then want to make sure we get our APT sources configured in our region:

```
cat > "/mnt/etc/apt/sources.list" << EOF
deb http://${REGION}.ec2.archive.ubuntu.com/ubuntu bionic main restricted universe multiverse
deb http://${REGION}.ec2.archive.ubuntu.com/ubuntu bionic-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu bionic-security main restricted universe multiverse
EOF
```

At this point we can mount the various filesystems required by the installation:

```
mount -t proc proc "/mnt/proc"
mount -t sysfs sysfs "/mnt/sys"
mount -o bind /dev "/mnt/dev"
mount -o bind /dev/pts "/mnt/dev/pts"
```

Finally let's download a copy of our `minimal-os` and `minimal-ec2-os` packages
and place them into our target system:

```
curl -L -o '/mnt/minimal-os.deb' \
  'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.0/minimal-os_1.0.0_all.deb'
curl -L -o '/mnt/minimal-ec2-os.deb' \
  'https://github.com/usrz/minimal-ubuntu/releases/download/v1.0.0/minimal-ec2-os_1.0.0_all.deb'
```

Minimal installation
--------------------

We continue the installation by chrooting into the target system using the `C`
locale (as no other locale has yet been generated):

```
eval $(LANG=C LC_ALL=C LANGUAGE=C locale) chroot "/mnt" /bin/bash --login
```

We then want to update the system, and install all packages required for a
minimal system (note that I don't know why `makedev` gets isntalled by
`debootstrap`, even when `--exclude=...` is specified):

```
export DEBIAN_FRONTEND=noninteractive

export APT_OPTIONS="-oAPT::Install-Recommends=false \
  -oAPT::Install-Suggests=false \
  -oAcquire::Languages=none"

apt-get $APT_OPTIONS update && \
  apt-get $APT_OPTIONS --yes dist-upgrade && \
  apt-get $APT_OPTIONS --yes install ./minimal-ec2-os.deb ./minimal-os.deb linux-aws
```

Then for sanity's sake, let's keep only the `minimal-ec2-os`, `minimal-os` and
`linux-aws` packages marked as _automatically installed_ (this will help with
`apt-get autoremove`):

```
apt-mark showmanual | xargs apt-mark auto
apt-mark manual minimal-ec2-os minimal-os linux-aws
```

Then we need to create create our `en_US.UTF8` locale and set it as our default:

```
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US
```

We continue by installing the GRUB boot loader:

```
findmnt -no SOURCE / | sed -E 's|[0-9]+$||g' | xargs grub-install && update-grub
```

We then want to restrict SSH to forbid password-based logins:

```
sed -i -E \
  -e 's/^#?\s*PasswordAuthentication\s+(yes|no)\s*$/PasswordAuthentication no/g' \
  -e 's/^#?\s*ChallengeResponseAuthentication\s+(yes|no)\s*$/ChallengeResponseAuthentication no/g' \
  /etc/ssh/sshd_config
```

Then let's disable the `getty` systemd target, as we don't really have
a console from which people can log in:

```
systemctl mask "getty@tty1.service"
systemctl mask "serial-getty@ttyS0.service"
```

Finally, let's make sure that the `minimal-ec2-os-setup` script runs upon
the first boot:

```
sed -i 's|^RUN_SETUP=.*$|RUN_SETUP=true|g' /etc/default/minimal-ec2-os-setup
```


Cleaning up
-----------

Let's clean up our APT state and exit the chrooted environment:

```
apt-get clean && exit
```

We then want to clean up a bunch of files left over by the installation, some
of them will be re-created once `minimal-ec2-os-setup` runs the first time:

```
rm -f /mnt/etc/hostname \
      /mnt/etc/hosts \
      /mnt/etc/ssh/ssh_host_*_key* \
      /mnt/minimal-ec2-os.deb \
      /mnt/root/.bash_history
```

At this point we can simply unmount our volume:

```
umount -Rlf /mnt
```

Creating an AMI
---------------

Going back to the EC2 console we can now detach the volume we created from the
EC2 instance we used for setup, and create a snapshot from it.

Once the snapshot is created, we can then create an image from it, using the
`x86_64` architecture, and `Hardware-assisted` virtualization.
