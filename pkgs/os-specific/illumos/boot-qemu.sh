#!/usr/bin/env bash
#
# Boot the cross-built illumos kernel under QEMU and watch it on the serial
# console.
#
#     ./pkgs/os-specific/illumos/boot-qemu.sh
#
# What it does:
#
#   * builds pkgsCross.x86_64-illumos.illumos.unix (the i86pc kernel),
#   * assembles a minimal boot archive: an old-style ASCII ("odc") cpio
#     holding unix, genunix, the loadable modules and the /etc binding files,
#     which is what
#     common/fs/bootrd_cpio.c -- one of the four readers in
#     uts/common/krtld/bootrd.c:47 -- knows how to read,
#   * wraps both in a GRUB2 multiboot rescue ISO with the console on ttya,
#   * runs qemu-system-x86_64 with that ISO and -serial stdio.
#
# How far it gets today: dboot hands over, unix relocates itself, krtld links
# genunix, the banner prints, startup_modules() loads specfs/devfs/dev/procfs,
# psm_modload() takes uppc, setup_ddi() probes the buses and builds the devinfo
# tree, configure() attaches the root nexus and the pseudo nexus, and main()
# reaches vfs_mountroot(). rootconf() loads and _init()s ufs, resolves the root
# device to the ramdisk, and then:
#
#     NOTICE: mount: not a UFS magic number (0x394d0000)
#     Cannot mount root on /ramdisk:a fstype ufs
#     panic[cpu0]: vfs_mountroot: cannot mount root
#
# which is correct: the archive assembled below is a cpio, and 0x394d is the
# first two bytes of "070707". Everything short of a real root filesystem now
# works; the next step is a UFS (or hsfs) image rather than more modules.
#
# Notes:
#
#   * GRUB2 does *not* put the kernel path in the multiboot command line, but
#     uts/i86pc/os/fakebop.c:1694 takes the first word of that line as
#     "boot-file"/"whoami" and krtld then tries to open it as the primary
#     module. Hence the path being repeated in the `multiboot` line below;
#     without it krtld looks for a module called "-B".
#   * The /etc data files are the real ones from the gate, not inventions:
#     uts/intel/os/{name_to_sysnum,minor_perm,driver_classes,dacf.conf}.
#     driver_aliases and path_to_inst are normally written by add_drv(8) on a
#     live system, so they are empty here, and name_to_major is synthesised --
#     see the comment on it below.
#
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
nixpkgs=${NIXPKGS:-$(cd "$here/../../.." && pwd)}
src=${ILLUMOS_SRC:-$HOME/src/illumos-gate/nix-cross/usr/src}
work=${WORK:-${TMPDIR:-/tmp}/illumos-boot}

if [ ! -d "$src/uts/intel/os" ]; then
    echo "$0: no illumos source at $src; set ILLUMOS_SRC to a usr/src" >&2
    exit 1
fi

build() {
    nix-build --substituters 'https://cache.nixos.org' \
        --cores 8 --max-jobs 1 --no-out-link "$nixpkgs" -A "$1"
}

unix=$(build pkgsCross.x86_64-illumos.illumos.unix)
grub=$(build grub2)
xorriso=$(build libisoburn)
cpio=$(build cpio)
qemu=$(build qemu)

rm -rf "$work"
mkdir -p "$work/ba/etc" "$work/iso/boot/grub" \
    "$work/iso/platform/i86pc/kernel/amd64"

# The boot archive. krtld resolves unix's DT_NEEDED [genunix] out of here, and
# modload() looks the rest up under kernel/<class>/amd64 and
# platform/i86pc/kernel/<class>/amd64. The unix derivation already lays its
# output out that way -- the module Makefiles' own $(ROOTMODULE) rules put them
# there -- so copy those two trees across whole. ($out/lib/libgenunix.so is
# deliberately left out: it is a link-time stub, not a loadable module.)
cp -RL --no-preserve=mode "$unix/kernel" "$unix/platform" "$work/ba/"
cp "$src/uts/intel/os/name_to_sysnum" "$src/uts/intel/os/minor_perm" \
   "$src/uts/intel/os/driver_classes" "$src/uts/intel/os/dacf.conf" \
   "$work/ba/etc/"
: >"$work/ba/etc/driver_aliases"
: >"$work/ba/etc/system"
echo '#' >"$work/ba/etc/path_to_inst"

# /etc/name_to_major is *not* a source file. uts/intel/os/name_to_major in the
# gate holds only the four majors that are pinned by ABI (md, devinfo, asy,
# did); on a real system add_drv(8) appends one line per installed driver at
# install time, and there is no add_drv here. Without the rest, the first thing
# setup_ddi() does -- getlongprop_buf() for "rootnex" -- panics with "Couldn't
# find major number for 'rootnex'". So synthesise it: one entry per driver
# module actually in the archive, numbered from 0 up, skipping the pinned ones.
reserved=$(awk '!/^#/ && NF == 2 { print $2 }' "$src/uts/intel/os/name_to_major")
cp "$src/uts/intel/os/name_to_major" "$work/ba/etc/name_to_major"
chmod u+w "$work/ba/etc/name_to_major"
major=0
for drv in $(find "$work/ba" -path '*/kernel/drv/amd64/*' -type f -printf '%f\n' | sort -u); do
    while echo "$reserved" | grep -qx "$major"; do major=$((major + 1)); done
    echo "$drv $major" >>"$work/ba/etc/name_to_major"
    major=$((major + 1))
done

( cd "$work/ba" && find . -type f | sed 's|^\./||' | sort |
    "$cpio/bin/cpio" -o -H odc ) >"$work/iso/platform/i86pc/boot_archive" 2>/dev/null

cp "$unix/platform/i86pc/kernel/amd64/unix" "$work/iso/platform/i86pc/kernel/amd64/"

cat >"$work/iso/boot/grub/grub.cfg" <<'EOF'
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=1
set default=0
menuentry "illumos" {
    multiboot /platform/i86pc/kernel/amd64/unix /platform/i86pc/kernel/amd64/unix -B console=ttya,input-console=ttya
    module /platform/i86pc/boot_archive type=rootfs
    boot
}
EOF

PATH="$grub/bin:$xorriso/bin:$PATH" \
    grub-mkrescue -o "$work/illumos.iso" "$work/iso" >"$work/mkrescue.log" 2>&1

echo "=== booting $work/illumos.iso (^A x to quit) ==="
exec "$qemu/bin/qemu-system-x86_64" \
    -display none -no-reboot -m 4096 \
    -cdrom "$work/illumos.iso" \
    -serial mon:stdio
