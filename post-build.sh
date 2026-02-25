#!/bin/sh

set -e

# Create the Grub environment blocks
grub-editenv $BINARIES_DIR/grubenv_a create
grub-editenv $BINARIES_DIR/grubenv_a set boot=0
grub-editenv $BINARIES_DIR/grubenv_a set validated=0
grub-editenv $BINARIES_DIR/grubenv_a set booted_once=0

grub-editenv $BINARIES_DIR/grubenv_b create
grub-editenv $BINARIES_DIR/grubenv_b set boot=1
grub-editenv $BINARIES_DIR/grubenv_b set validated=0
grub-editenv $BINARIES_DIR/grubenv_b set booted_once=0

cp $BINARIES_DIR/grubenv_a $BINARIES_DIR/grubenv_a_valid
grub-editenv $BINARIES_DIR/grubenv_a_valid set booted_once=1
grub-editenv $BINARIES_DIR/grubenv_a_valid set validated=1

cp $BINARIES_DIR/grubenv_b $BINARIES_DIR/grubenv_b_valid
grub-editenv $BINARIES_DIR/grubenv_b_valid set booted_once=1
grub-editenv $BINARIES_DIR/grubenv_b_valid set validated=1

# Copy MBR boot code boot.img
cp $TARGET_DIR/lib/grub/i386-pc/boot.img $BINARIES_DIR

# Copy everything that's needed to build firmware images over to the
# output directory so that it can be bundled with the system image.
cp $NERVES_DEFCONFIG_DIR/grub.cfg $BINARIES_DIR

# Remove the Buildroot-generated grub.cfg so avoid confusion.
# We put our grub in the FAT filesystem at the beginning of the
# disk so that it exists across firmware updates.
rm -fr $TARGET_DIR/boot/grub/*

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
NERVES_SYSTEM=$BASE_DIR $HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR

# Helper: download a file using whichever tool is available
download() {
  if command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    curl -sSL -o "$2" "$1"
  fi
}

# --- Container runtime binaries (downloaded at build time) ---
PODMAN_VERSION="v5.7.1"
CONMON_VERSION="v2.1.13"
CRUN_VERSION="1.25.1"
NETAVARK_VERSION="v1.17.0"
AARDVARK_DNS_VERSION="v1.17.0"
CATATONIT_VERSION="v0.2.1"

mkdir -p "$TARGET_DIR/usr/bin" "$TARGET_DIR/usr/lib/podman"

# podman (remote-static build, ships as a tarball)
PODMAN_TAR="podman-remote-static-linux_amd64.tar.gz"
download "https://github.com/containers/podman/releases/download/${PODMAN_VERSION}/${PODMAN_TAR}" "/tmp/${PODMAN_TAR}"
tar xzf "/tmp/${PODMAN_TAR}" -C /tmp
cp /tmp/bin/podman-remote-static-linux_amd64 "$TARGET_DIR/usr/bin/podman"
chmod 755 "$TARGET_DIR/usr/bin/podman"
rm -rf "/tmp/${PODMAN_TAR}" /tmp/bin

# conmon
download "https://github.com/containers/conmon/releases/download/${CONMON_VERSION}/conmon.amd64" \
  "$TARGET_DIR/usr/bin/conmon"
chmod 755 "$TARGET_DIR/usr/bin/conmon"

# crun
download "https://github.com/containers/crun/releases/download/${CRUN_VERSION}/crun-${CRUN_VERSION}-linux-amd64" \
  "$TARGET_DIR/usr/bin/crun"
chmod 755 "$TARGET_DIR/usr/bin/crun"

# netavark (ships gzipped)
download "https://github.com/containers/netavark/releases/download/${NETAVARK_VERSION}/netavark.gz" \
  "/tmp/netavark.gz"
gunzip -f /tmp/netavark.gz
cp /tmp/netavark "$TARGET_DIR/usr/lib/podman/netavark"
chmod 755 "$TARGET_DIR/usr/lib/podman/netavark"
rm -f /tmp/netavark

# aardvark-dns (ships gzipped)
download "https://github.com/containers/aardvark-dns/releases/download/${AARDVARK_DNS_VERSION}/aardvark-dns.gz" \
  "/tmp/aardvark-dns.gz"
gunzip -f /tmp/aardvark-dns.gz
cp /tmp/aardvark-dns "$TARGET_DIR/usr/lib/podman/aardvark-dns"
chmod 755 "$TARGET_DIR/usr/lib/podman/aardvark-dns"
rm -f /tmp/aardvark-dns

# catatonit
download "https://github.com/openSUSE/catatonit/releases/download/${CATATONIT_VERSION}/catatonit.x86_64" \
  "$TARGET_DIR/usr/lib/podman/catatonit"
chmod 755 "$TARGET_DIR/usr/lib/podman/catatonit"

# Optional: Docker Compose V2 (~59 MB static binary). Off by default; set NERVES_SYSTEM_DOCKER_COMPOSE=1
# when building the system to include it. DOCKER_HOST is set in erlinit.config for Podman.
if [ -n "${NERVES_SYSTEM_DOCKER_COMPOSE:-}" ]; then
  COMPOSE_VERSION="v2.24.5"
  COMPOSE_BINARY="docker-compose-linux-x86_64"
  download "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/${COMPOSE_BINARY}" \
    "$TARGET_DIR/usr/bin/docker-compose"
  chmod 755 "$TARGET_DIR/usr/bin/docker-compose"
fi
