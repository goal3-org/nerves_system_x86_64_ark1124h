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

# Build grub.img ourselves, over the one Buildroot made. Buildroot bakes the
# prefix "(hd0,msdos1)/boot/grub" into it, so GRUB reads grub.cfg from the
# BIOS's first disk, which is only the disk GRUB came from when the BIOS
# renumbers the boot device to hd0. With "(,msdos1)/boot/grub" GRUB fills in
# the disk it was actually loaded from; grub.cfg then keeps the kernel and
# rootfs on that disk too (regexp and probe are built in for that).
GRUB_MODULES="boot linux ext2 squash4 fat part_msdos normal biosdisk loadenv echo true test sleep regexp probe"
GRUB_MODULE_DIR=$TARGET_DIR/lib/grub/i386-pc
for m in $GRUB_MODULES; do
    [ -f $GRUB_MODULE_DIR/$m.mod ] || { echo "post-build.sh: GRUB module $m.mod missing in $GRUB_MODULE_DIR" >&2; exit 1; }
done
$HOST_DIR/bin/grub-mkimage -d $GRUB_MODULE_DIR -O i386-pc -o $BINARIES_DIR/grub.img \
    -p "(,msdos1)/boot/grub" $GRUB_MODULES
# fwup.conf writes grub.img at sector 1, in front of the first partition.
GRUB_IMG_SIZE=$(stat -c %s $BINARIES_DIR/grub.img)
[ "$GRUB_IMG_SIZE" -lt 262144 ] || { echo "post-build.sh: grub.img is $GRUB_IMG_SIZE bytes, over the 256K before the first partition" >&2; exit 1; }

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

# --- Container runtime (podman-static: full podman + conmon + crun + netavark + aardvark-dns + catatonit) ---
PODMAN_VERSION="v5.8.0"
PODMAN_TAR="podman-linux-amd64.tar.gz"
PODMAN_EXTRACT="/tmp/podman-linux-amd64"

mkdir -p "$TARGET_DIR/usr/bin" "$TARGET_DIR/usr/lib/podman"

download "https://github.com/mgoltzsche/podman-static/releases/download/${PODMAN_VERSION}/${PODMAN_TAR}" "/tmp/${PODMAN_TAR}"
tar xzf "/tmp/${PODMAN_TAR}" -C /tmp

cp "${PODMAN_EXTRACT}/usr/local/bin/podman"  "$TARGET_DIR/usr/bin/podman"
cp "${PODMAN_EXTRACT}/usr/local/bin/crun"    "$TARGET_DIR/usr/bin/crun"
cp "${PODMAN_EXTRACT}/usr/local/lib/podman/conmon"       "$TARGET_DIR/usr/bin/conmon"
cp "${PODMAN_EXTRACT}/usr/local/lib/podman/netavark"     "$TARGET_DIR/usr/lib/podman/netavark"
cp "${PODMAN_EXTRACT}/usr/local/lib/podman/aardvark-dns" "$TARGET_DIR/usr/lib/podman/aardvark-dns"
cp "${PODMAN_EXTRACT}/usr/local/lib/podman/catatonit"    "$TARGET_DIR/usr/lib/podman/catatonit"

chmod 755 "$TARGET_DIR/usr/bin/podman" \
          "$TARGET_DIR/usr/bin/crun" \
          "$TARGET_DIR/usr/bin/conmon" \
          "$TARGET_DIR/usr/lib/podman/netavark" \
          "$TARGET_DIR/usr/lib/podman/aardvark-dns" \
          "$TARGET_DIR/usr/lib/podman/catatonit"

rm -rf "/tmp/${PODMAN_TAR}" "${PODMAN_EXTRACT}"

# Optional: Docker Compose V2 (~59 MB static binary). Off by default; set NERVES_SYSTEM_DOCKER_COMPOSE=1
# when building the system to include it. DOCKER_HOST is set in erlinit.config for Podman.
if [ -n "${NERVES_SYSTEM_DOCKER_COMPOSE:-}" ]; then
  COMPOSE_VERSION="v2.24.5"
  COMPOSE_BINARY="docker-compose-linux-x86_64"
  download "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/${COMPOSE_BINARY}" \
    "$TARGET_DIR/usr/bin/docker-compose"
  chmod 755 "$TARGET_DIR/usr/bin/docker-compose"
fi
