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
#
# Core:         autotools, compiler, headers
# Optional:     available Alpine packages for hwloc backends.
#               Proprietary libraries (CUDA, NVML, ROCm, etc.) are not
#               packaged in Alpine — configure skips them automatically.
# ---------------------------------------------------------------------------
apk add --no-cache \
    bash \
    build-base \
    autoconf \
    automake \
    libtool \
    linux-headers \
    pkgconfig \
    file

apk add --no-cache \
    libpciaccess-dev \
    libxml2-dev \
    ncurses-dev \
    zlib-dev \
    eudev-dev

# Cairo / X11 (graphical lstopo output)
apk add --no-cache \
    cairo-dev \
    libx11-dev libxext-dev libxrender-dev \
    pixman-dev freetype-dev fontconfig-dev

# Level Zero (Intel GPU discovery)
apk add --no-cache level-zero-dev 2>/dev/null || true

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
# No --disable-* flags are passed: configure auto-detects all available
# features.  On Alpine, only open-source backends (PCI, XML, udev, etc.)
# are available; proprietary backends (CUDA, NVML, ROCm, etc.) are skipped
# gracefully by configure.
# ---------------------------------------------------------------------------
./configure \
    --prefix="${PREFIX}" \
    --enable-static \
    --disable-shared \
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

# BusyBox tar (Alpine default) lacks --transform, so create a temporary
# version-named directory and tar that instead.
STAGING=$(mktemp -d)
mkdir -p "${STAGING}/hwloc-${VERSION}"
cp -a "${PREFIX}/bin/." "${STAGING}/hwloc-${VERSION}/"
tar czf "${DISTDIR}/${ARCHIVE}" -C "${STAGING}" "hwloc-${VERSION}"
rm -rf "${STAGING}"

# ---------------------------------------------------------------------------
# Print a summary of what was built
# ---------------------------------------------------------------------------
cd "${PREFIX}/bin"

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
