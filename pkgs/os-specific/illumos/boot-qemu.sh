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
#     holding unix, genunix and the /etc binding files, which is what
#     common/fs/bootrd_cpio.c -- one of the four readers in
#     uts/common/krtld/bootrd.c:47 -- knows how to read,
#   * wraps both in a GRUB2 multiboot rescue ISO with the console on ttya,
#   * runs qemu-system-x86_64 with that ISO and -serial stdio.
#
# How far it gets today: dboot hands over, unix relocates itself, krtld links
# genunix, the kernel prints its banner and then stops at "(Can't load specfs)"
# -- the boot archive has no filesystem modules in it, because nothing under
# uts/intel besides genunix is packaged yet. Everything up to and including
# module loading works.
#
# Notes:
#
#   * GRUB2 does *not* put the kernel path in the multiboot command line, but
#     uts/i86pc/os/fakebop.c:1694 takes the first word of that line as
#     "boot-file"/"whoami" and krtld then tries to open it as the primary
#     module. Hence the path being repeated in the `multiboot` line below;
#     without it krtld looks for a module called "-B".
#   * The /etc data files are the real ones from the gate, not inventions:
#     uts/intel/os/{name_to_major,name_to_sysnum,minor_perm,driver_classes}.
#     driver_aliases and path_to_inst are normally written by add_drv(8) on a
#     live system, so they are empty here.
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
mkdir -p "$work/ba/kernel/amd64" "$work/ba/platform/i86pc/kernel/amd64" \
    "$work/ba/etc" "$work/iso/boot/grub" "$work/iso/platform/i86pc/kernel/amd64"

# The boot archive. krtld resolves unix's DT_NEEDED [genunix] out of here.
cp "$unix/kernel/amd64/genunix"                  "$work/ba/kernel/amd64/"
cp "$unix/platform/i86pc/kernel/amd64/unix"      "$work/ba/platform/i86pc/kernel/amd64/"
cp "$src/uts/intel/os/name_to_major"  "$src/uts/intel/os/name_to_sysnum" \
   "$src/uts/intel/os/minor_perm"     "$src/uts/intel/os/driver_classes" \
   "$work/ba/etc/"
: >"$work/ba/etc/driver_aliases"
: >"$work/ba/etc/system"
echo '#' >"$work/ba/etc/path_to_inst"

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
