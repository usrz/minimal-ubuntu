MINIMAL OS SETUP SCRIPT
-----------------------

This directory contains the various scripts required to set up the "minimal-os"
set of packages.

Each individual package will put their necessary scripts in this directory, and
link them into "/usr/lib/minimal-os-setup.d", then the "minimal-os-setup" script
will run them upon the _first_ startup.
