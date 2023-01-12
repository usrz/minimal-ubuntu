# ============================================================================ #
# MAKE FILE FOR MINIMAL UBUNTU PACKAGES                                        #
# ============================================================================ #

.DEFAULT_GOAL := all
.PHONY        := all deb

BASEDIR       ?= $(realpath .)

export BASEDIR

# ============================================================================ #
# SUBDIR MAKEFILE: build package in directory                                  #
# ============================================================================ #
ifeq ($(MAKELEVEL),1)

# Variables from our control file
PACKAGE      := $(shell cat "DEBIAN/control" | awk '/^Package: / { print $$2 }')
VERSION      := $(shell cat "DEBIAN/control" | awk '/^Version: / { print $$2 }')
ARCHITECTURE := $(shell cat "DEBIAN/control" | awk '/^Architecture: / { print $$2 }')
DISTRIBUTION := $(shell cat "DEBIAN/control" | awk '/^Distribution: / { print $$2 }')
COMPONENT    := $(shell cat "DEBIAN/control" | awk '/^Component: / { print $$2 }')

# Our "package.deb" file name
DEB_NAME     := $(PACKAGE)_$(VERSION)$(BUILD)_$(ARCHITECTURE).deb
DEB_FILE     := $(BASEDIR)/$(DEB_NAME)

# Build the debian package with the correct naming structure
deb:
	@echo "Building \`$(DEB_NAME)' package (version $(VERSION))"
	@dpkg-deb --root-owner-group --build . "$(DEB_FILE)" > /dev/null

endif

# ============================================================================ #
# MAIN MAKEFILE: find subdirectories and invoke recursively                    #
# ============================================================================ #
ifeq ($(MAKELEVEL),0)

all:
	@for SUBDIR in $$(ls -1 */DEBIAN/control | cut -d/ -f1) ; do \
		$(MAKE) -f "$(realpath $(MAKEFILE_LIST))" -C "$${SUBDIR}" "deb" ; \
	done

clean:
	rm -f *.deb

endif
