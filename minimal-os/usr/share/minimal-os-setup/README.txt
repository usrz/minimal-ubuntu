MINIMAL OS SETUP SCRIPT
-----------------------

The "minimal-os-setup" script runs once, upon first boot of the system, and
perform the initial setup required.

The various "minimal-os" packages enable it in their "postinst" script, and
add the various required script to run in the "/usr/lib/minimal-os-setup.d"
directory.

The "/usr/share/minimal-os-setup/common-functions" script contains common
functions that can be invoked by sub-packages.
