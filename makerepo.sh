#!/bin/bash -e

# Copy our DEB packages in the repo's pool
rm -rf "./repo"
mkdir -p "./repo/pool"
cp *.deb "./repo/pool"

# The output directory of our repository
OUTDIR="${PWD}/repo/dists/nodistro"
CFGFILE="${PWD}/repository.conf"

# Let's start...
pushd "./repo" >> "/dev/null"

# Generate all the "Packages" and "Contents" files
for ARCH in "amd64" "arm64" "i386" ; do
  # Per-architecture output directory
  BINDIR="${OUTDIR}/main/binary-${ARCH}"
  mkdir -p "${BINDIR}"

  # Generate the "Packages" file
  echo "Generating ${BINDIR}/Packages"
  apt-ftparchive -c "${CFGFILE}" --arch="${ARCH}" packages "pool" > "${BINDIR}/Packages"

  gzip -c9 "${BINDIR}/Packages" > "${BINDIR}/Packages.gz"
  xz -c9 "${BINDIR}/Packages" > "${BINDIR}/Packages.xz"

  # Generate the "Contents" file
  echo "Generating ${OUTDIR}/Contents-${ARCH}"
  apt-ftparchive -c "${CFGFILE}" --arch="${ARCH}" contents "pool" > "${OUTDIR}/Contents-${ARCH}"
  gzip -c9 "${OUTDIR}/Contents-${ARCH}" > "${OUTDIR}/Contents-${ARCH}.gz"
done

# Generate the "Release" file
echo "Generating ${OUTDIR}/Release"
apt-ftparchive -c "${CFGFILE}" release "${OUTDIR}" > "${OUTDIR}/.Release.tmp"
mv "${OUTDIR}/.Release.tmp" "${OUTDIR}/Release"

# Detached signature in "Release.gpg" and clearsigned in "InRelease"
if test -z "${GPG_PASSWORD}" ; then
  read -s -p "GPG key password: " GPG_PASSWORD
  echo '' # Newline
fi

echo "Generating ${OUTDIR}/Release.gpg"
echo "${GPG_PASSWORD}" | gpg1 --batch --quiet --passphrase-fd 0 \
  --local-user 3001B2B0 --output "${OUTDIR}/Release.gpg" \
  --armor --detach-sign --sign "${OUTDIR}/Release"

echo "Generating ${OUTDIR}/InRelease"
echo "${GPG_PASSWORD}" | gpg1 --batch --quiet --passphrase-fd 0 \
  --local-user 3001B2B0 --output "${OUTDIR}/InRelease" \
  --armor --clearsign "${OUTDIR}/Release"

# Export GPG public key in ASCII and binary format
gpg1 --armor --export 3001B2B0 > "./minimal-ubuntu.gpg.asc"
gpg1 --export 3001B2B0 > "./minimal-ubuntu.gpg"

# Generate all our index files
echo "Generating index files"

popd >> "/dev/null"
for DIR in $(find repo -type d) ; do
  NAME=$(echo "${DIR}" | sed 's|^repo|minimal-ubuntu|')
  cat <<EOF > "${DIR}/index.html"
<!DOCTYPE html>
<html>
  <head>
    <title>Index of ${NAME}</title>
    <style>
      body { font-family: sans-serif; margin: 2em; }
      a { text-decoration: none; color: #0077cc; }
      a:hover { text-decoration: underline; }
      small { color: #777; }
    </style>
  </head>
  <body>
<h1><small>Index of</small> ${NAME}</h1>

$(test "${DIR}" != "repo" && echo '<div>&#x1F4C2; <a href="..">..</a></div>')
$(find "${DIR}" -mindepth 1 -maxdepth 1 -type d -not -name '.*' -printf '<div>&#x1F4C2; <a href="%f">%f</a>/</div>\n' | sort)
$(find "${DIR}" -mindepth 1 -maxdepth 1 -type f -not -name '.*' -not -name index.html -printf '<div>&#x1F4C4; <a href="%f">%f</a> <small>%s bytes</small></div>\n' | sort)
    <hr>
    <small>Generated on $(date)</small>
  </body>
</html>
EOF
done
