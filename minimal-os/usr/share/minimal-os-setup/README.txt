MINIMAL OS SETUP SCRIPT
-----------------------

The "minimal-os-setup" script runs once, upon first boot of the system, and
perform the initial setup required.

The "minimal-os" package enables it in its "postinst" script, and the various
scripts to run are found in the "/usr/lib/minimal-os-setup.d" directory.

The "/usr/share/minimal-os-setup/common-functions" script contains common
functions that can be invoked by sub-packages.
