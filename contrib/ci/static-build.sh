#!/usr/bin/env sh
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Build fully static hwloc executables with musl libc (Alpine Linux).
#
# Usage:
#   docker run --platform linux/amd64 -v $PWD:/work -w /work \
#     -e VERSION=3.0.0 -e ARCH=x86_64 \
#     alpine:3.20 /work/contrib/ci/static-build.sh
#
# The resulting tarball is written to /work/dist/.
#
# Based on: https://github.com/open-mpi/hwloc/wiki/StaticBuild

set -ex

: "${VERSION:?VERSION must be set}"
: "${ARCH:?ARCH must be set (e.g. x86_64, aarch64)}"

PREFIX=/tmp/hwloc-install
DISTDIR=/work/dist

# ---------------------------------------------------------------------------
# Install build dependencies
# ---------------------------------------------------------------------------
apk add --no-cache \
    build-base \
    autoconf \
    automake \
    libtool \
    linux-headers \
    pkgconfig \
    file

# ---------------------------------------------------------------------------
# Bootstrap autotools (configure is not committed to git)
# ---------------------------------------------------------------------------
./autogen.sh

# ---------------------------------------------------------------------------
# Configure for a fully static build
#
# hwloc's build system uses libtool.  Passing LDFLAGS=--static at configure
# time works because libtool ignores "--static" and passes it through to
# GCC, which interprets it the same as -static.
#
# At make time we additionally pass LDFLAGS=-all-static so that libtool
# itself knows to link fully static programs (without this, libtool may
# still build shared objects or libtool wrappers).
#
# All optional hardware-discovery backends (PCI, GPU, etc.) are explicitly
# disabled to avoid pulling in shared-library dependencies and to keep the
# resulting binaries small and portable.
# ---------------------------------------------------------------------------
./configure \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared \
    --disable-pci \
    --disable-cuda \
    --disable-nvml \
    --disable-opencl \
    --disable-rsmi \
    --disable-levelzero \
    --disable-gl \
    --disable-libxml2 \
    --disable-cairo \
    --disable-plugins \
    --disable-libudev \
    LDFLAGS="--static"

# ---------------------------------------------------------------------------
# Build and install
#
# -all-static tells libtool to pass -static to the linker, producing
# binaries with no dynamic dependencies whatsoever.
# ---------------------------------------------------------------------------
make -j"$(nproc)" LDFLAGS=-all-static
make install-strip

# ---------------------------------------------------------------------------
# Package the installed binaries
# ---------------------------------------------------------------------------
ARCHIVE="hwloc-${VERSION}-linux-${ARCH}-static.tar.gz"
mkdir -p "${DISTDIR}"

cd "${PREFIX}/bin"
tar czf "${DISTDIR}/${ARCHIVE}" \
    --transform="s|^|hwloc-${VERSION}/|" \
    .

# ---------------------------------------------------------------------------
# Print a summary of what was built
# ---------------------------------------------------------------------------
echo ""
echo "========================================="
echo "  Built: ${ARCHIVE}"
echo "========================================="
echo ""
echo "Contents:"
tar tzf "${DISTDIR}/${ARCHIVE}" | sed 's/^/  /'

echo ""
echo "Binary info:"
file ./*

# Verify they are truly static
echo ""
echo "Dynamic dependency check (should all show 'not a dynamic executable'):"
for f in *; do
    if [ -x "$f" ] && file "$f" | grep -q ELF; then
        ldd "$f" 2>&1 | head -1
    fi
done | sed 's/^/  /'
