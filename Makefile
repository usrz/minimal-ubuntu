# ============================================================================ #
# MAKE FILE FOR MINIMAL UBUNTU PACKAGES                                        #
# ============================================================================ #

.DEFAULT_GOAL := all
.PHONY        := all clean distclean publish

BASEDIR       ?= $(realpath .)
DISTDIR       ?= $(BASEDIR)/dist
BUILD         ?= $(if $(CIRCLE_BUILD_NUM),-circle$(CIRCLE_BUILD_NUM))

export BASEDIR DISTDIR BUILD

# ============================================================================ #
# SUBDIR MAKEFILE                                                              #
#                                                                              #
# Simply copy the source tree into "./dist", update the package control file,  #
# then build and/or upload our package                                         #
# ============================================================================ #
ifeq ($(MAKELEVEL),1)

# Variables from our control file
PACKAGE      := $(shell cat "DEBIAN/control" | awk '/^Package: / { print $$2 }')
VERSION      := $(shell cat "DEBIAN/control" | awk '/^Version: / { print $$2 }')
ARCHITECTURE := $(shell cat "DEBIAN/control" | awk '/^Architecture: / { print $$2 }')
DISTRIBUTION := $(shell cat "DEBIAN/control" | awk '/^Distribution: / { print $$2 }')
COMPONENT    := $(shell cat "DEBIAN/control" | awk '/^Component: / { print $$2 }')

# Defaults if not specified in control
DISTRIBUTION := $(or $(DISTRIBUTION),bionic)
COMPONENT    := $(or $(COMPONENT),main)

# Other variables
DEB          := $(PACKAGE)_$(VERSION)$(BUILD)_$(ARCHITECTURE).deb

# Copy all the package contents and update the "control" file
$(DISTDIR)/$(PACKAGE):
	@echo " ~~~ Preparing \`$(@)' directory structure"
	@mkdir -p "$(@)"
	@echo " ~~~ Copying \`$(realpath .)' directory contents"
	@cp -R "." "$(@)/."
	@echo " ~~~ Updating \`$(@)/DEBIAN/control' debian control file"
	@sed -E -i.bak \
		-e 's|(^Version: .*)|&$(BUILD)|g' \
		-e '/^Distribution: /d' \
		-e '/^Component: /d' \
		"$(@)/DEBIAN/control"
	@rm -f "$(@)/DEBIAN/control.bak"

# Build the debian package with the correct naming structure
$(BASEDIR)/$(DEB): $(DISTDIR)/$(PACKAGE)
	@echo " ~~~ Building \`$(@)' package (version $(VERSION)$(BUILD))"
	@dpkg-deb -b --root-owner-group "$(DISTDIR)/$(PACKAGE)" "$(@)" > /dev/null

# Clean up the "./dist/{package_name}" directory
clean:
	@echo " ~~~ Cleaning \`$(DISTDIR)/$(PACKAGE)' build directory"
	@rm -rf "$(DISTDIR)/$(PACKAGE)"

# Clean up the built debian pacakge
distclean: clean
	@echo " ~~~ Removing \`$(BASEDIR)/$(DEB)' debian package"
	@rm -f "$(BASEDIR)/$(DEB)"


# Build the debian package based on variables
all: $(BASEDIR)/$(DEB)

endif

# ============================================================================ #
# MAIN MAKEFILE                                                                #
#                                                                              #
# Define our sub-directories to build from and invoke recursively              #
# ============================================================================ #
ifeq ($(MAKELEVEL),0)

%:
	@for SUBDIR in $$(ls -1 */DEBIAN/control | cut -d/ -f1) ; do \
		$(MAKE) --no-print-directory -f "$(realpath $(MAKEFILE_LIST))" -C "$${SUBDIR}" "$(@)" ; \
	done

endif
