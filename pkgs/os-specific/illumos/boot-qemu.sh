#!/usr/bin/env bash
#
# Boot the cross-built illumos kernel under QEMU and watch it on the serial
# console.
#
#     ./pkgs/os-specific/illumos/boot-qemu.sh
#
# What it does:
#
#   * builds pkgsCross.x86_64-illumos.illumos.unix (the i86pc kernel) and
#     pkgsCross.x86_64-illumos.illumos.init-stub (a freestanding /sbin/init),
#   * assembles a minimal root filesystem: unix, genunix, the loadable modules,
#     the /etc binding files, the mount points the kernel puts its own
#     synthetic filesystems on, and /sbin/init,
#   * turns that into an *iso9660* image, which is the boot archive,
#   * wraps both in a GRUB2 multiboot rescue ISO with the console on ttya,
#   * runs qemu-system-x86_64 with that ISO and -serial stdio.
#
# Why iso9660 and not cpio: the boot archive reaches the kernel as a ramdisk
# whose block device (/ramdisk:a) is the loaded multiboot module byte for byte.
# Nothing unpacks it -- impl_setup_ddi() in uts/i86pc/os/ddi_impl.c just hands
# ramdisk_start/ramdisk_end to drv/ramdisk as its "existing" property -- so the
# archive has to *be* a filesystem image. A cpio archive is readable only by
# krtld's bcpio_ops (uts/common/krtld/bootrd.c); there is no cpio entry in
# uts/common/os/vfs_conf.c, so it can never be a root filesystem. That is
# exactly what the old panic was saying: "not a UFS magic number (0x394d0000)",
# and 0x394d is "9M", the first two bytes of cpio's 070707 magic.
#
# Of the four formats bootadm(8) knows (bam_formats[] in cmd/boot/bootadm:
# hsfs, ufs, cpio, ufs-nocompress), hsfs is the only one we can synthesise on a
# Linux build host. mkfs_ufs is a *target* program and will not run here, and
# illumos UFS is not interchangeable with BSD FFS1 in the places that matter --
# struct direct in uts/common/sys/fs/ufs_fsdir.h has a 16-bit d_namlen exactly
# where FreeBSD's makefs writes a d_type byte followed by an 8-bit namlen, so
# every directory entry would be misread. hsfs we get from xorrisofs for free;
# hsfs_mountroot() (uts/common/fs/hsfs/hsfs_vfsops.c) takes its device from a
# plain getrootdev() with nothing CD-specific about it, so no disk driver stack
# is needed; and krtld's standalone iso9660 reader is already linked into unix
# (hsfs.o in KRTLD_OBJS, bhsfs_ops in bfs_tab[]).
#
# How far it gets today: dboot hands over, unix relocates itself, krtld links
# genunix, the banner prints, startup_modules() loads the boot-time modules,
# psm_modload() takes uppc, setup_ddi() probes the buses and builds the devinfo
# tree, configure() attaches the root and pseudo nexuses, and vfs_mountroot()
# mounts hsfs on /ramdisk:a -- and then keeps going, mounting devfs, dev, ctfs,
# objfs, bootfs, mntfs, sharefs and tmpfs on top of it, all without a warning.
# main() then reaches strplumb(), which loads and reports the one failure we
# expect and want ("strplumb: failed to initialize drv/dld" -- the IP stack is
# not packaged), and then consconfig().
#
# consconfig() completes, main() forks init, and init runs: `/sbin/init` is
# exec'd and executes user instructions. Two independent checks, because the
# console makes this much harder to see than it should be (below):
#
#   * `illumos.init-stub` ends in uadmin(A_SHUTDOWN, AD_POWEROFF). The machine
#     powers off and qemu exits after about 13 seconds instead of sitting
#     there until the harness kills it. Nothing but that syscall does that.
#   * Booting an init that is nothing but an infinite userland `nop` loop and
#     sampling registers through the qemu monitor gives RIP=0x000000000040007c
#     at CPL=3 -- the process's own text, in user mode.
#
# and the kernel says so itself, if you can see it: with prom_io_use_kernel()
# stubbed out (below) the tail of the boot is
#
#     strplumb: failed to initialize drv/dld
#     NOTICE: MPO disabled because memory is interleaved
#
#     syncing file systems... done
#
# -- the uadmin() shutdown path, reached only from user mode.
#
# The one thing that is still wrong, and the thing to fix next: **after
# consconfig(), kernel console output goes nowhere.** The last line you see on
# either console is the strplumb one, on serial and on VGA alike (checked by
# screendumping the VGA text console through the qemu monitor during a
# serial-console boot, and by booting with the console on VGA instead). It is
# not a hang -- everything above still happens, silently.
#
# The mechanism is understood. console_putchar() falls back to prom_putchar()
# until a user process has the console stream open, prom_putchar() goes through
# `sysp`, and consconfig_init_input() calls prom_io_use_kernel()
# (common/io/consconfig_dacf.c:1499) which repoints `sysp` at kern_sysp --
# sysp_putchar/sysp_getchar/sysp_ischar in uts/i86pc/os/machdep.c, all of which
# route to cons_polledio. In this configuration that polled console does not
# reach the emulated 16550, so output is dropped on the floor and input never
# arrives. Stubbing prom_io_use_kernel() out to a no-op, so that `sysp` stays
# on the boot console, brings every message back; that is a debugging hack, not
# a fix, but it is how the ENOEXEC below was found, and it is worth a couple of
# minutes to anyone debugging anything past this point.
#
# (Historical note, because it cost real time: before exec/elfexec was
# packaged, this same silence hid an exec failure. The kernel was busy-looping
# in sysp_ischar() from prom_getchar(), reached from prom_reboot_prompt() via
# prom_exit_to_mon() from halt("unix: Could not start init") -- confirmed by
# attaching gdb to the qemu gdbstub, where the backtrace showed
# prom_reboot_prompt on a thread_start stack, i.e. the init thread rather than
# main()'s. With prom_io_use_kernel() stubbed, the kernel says so itself:
# "WARNING: exec(/sbin/init) failed with errno 8".)
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
init=$(build pkgsCross.x86_64-illumos.illumos.init-stub)
grub=$(build grub2)
xorriso=$(build libisoburn)

# qemu is not part of what we are testing, and on a checkout that has moved
# ahead of the binary cache `nix-build -A qemu` is a source build of qemu *and*
# its whole doc/test toolchain (python3, itstool, zopfli, xvfb, and from there
# LLVM) -- hours, for a program the user almost certainly already has. Prefer
# whatever is on $PATH and only build one as a fallback.
if qemu=$(command -v qemu-system-x86_64); then
    echo "using qemu-system-x86_64 from PATH: $qemu"
else
    echo "no qemu-system-x86_64 on PATH; building one (this can take a while)"
    qemu="$(build qemu)/bin/qemu-system-x86_64"
    echo "using $qemu"
fi

rm -rf "$work"
mkdir -p "$work/ba/etc" "$work/iso/boot/grub" \
    "$work/iso/platform/i86pc/kernel/amd64"

# The boot archive. krtld resolves unix's DT_NEEDED [genunix] out of here, and
# modload() looks the rest up under kernel/<class>/amd64 and
# platform/i86pc/kernel/<class>/amd64. The unix derivation already lays its
# output out that way -- the module Makefiles' own $(ROOTMODULE) rules put them
# there -- so copy those two trees across whole. ($out/lib/libgenunix.so is
# deliberately left out: it is a link-time stub, not a loadable module.)
# ($out/usr comes along too: kobj's module search path is "/system/boot/kernel
# /platform/i86pc/kernel /kernel /usr/kernel", and a couple of modules install
# themselves under $(USR_EXEC_DIR) rather than the root one -- shbinexec, for
# instance.)
cp -RL --no-preserve=mode "$unix/kernel" "$unix/platform" "$unix/usr" "$work/ba/"
cp "$src/uts/intel/os/name_to_sysnum" "$src/uts/intel/os/minor_perm" \
   "$src/uts/intel/os/driver_classes" "$src/uts/intel/os/dacf.conf" \
   "$work/ba/etc/"
# /etc/driver_aliases is written by add_drv(8) from the `alias=` attributes on
# the `driver` actions in the packaging manifests, so it has to be synthesised
# too. These are copied verbatim from the gate:
# pkg/manifests/driver-i86pc-platform.p5m (asy), system-kernel.p5m (kb8042,
# mouse8042, pseudo) and system-kernel-platform.p5m (isa). Without the
# `pseudo zconsnex` line, i_ndi_make_spec_children() complains
# "init_spec_child: parent=pseudo, bad spec (zconsnex)" on every boot.
cat >"$work/ba/etc/driver_aliases" <<'EOF'
asy "pciclass,0700"
asy "pci11c1,480"
isa "pciclass,060100"
kb8042 "pnpPNP,303"
mouse8042 "pnpPNP,f03"
pseudo "zconsnex"
EOF
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
    # Skip anything the gate already pins. asy(4D) in particular is both in
    # the source file (major 106) and in the archive, and a duplicate entry
    # loses the driver its major -- which quietly costs you the serial
    # console, since consconfig() resolves ttya by ddi_name_to_major("asy").
    awk -v d="$drv" '!/^#/ && $1 == d { found = 1 } END { exit !found }' \
        "$work/ba/etc/name_to_major" && continue
    while echo "$reserved" | grep -qx "$major"; do major=$((major + 1)); done
    echo "$drv $major" >>"$work/ba/etc/name_to_major"
    major=$((major + 1))
done

# Mount points. vfs_mountroot() does not stop at the root: it goes on to mount
# devfs on /devices, dev on /dev, and then ctfs, objfs, bootfs, mntfs, sharefs
# and tmpfs on the paths below. hsfs is read-only, so each of these has to
# already exist in the image or the mount is a "Cannot mount ..." warning.
mkdir -p "$work/ba/dev" "$work/ba/devices" "$work/ba/proc" "$work/ba/tmp" \
    "$work/ba/system/contract" "$work/ba/system/object" "$work/ba/system/boot" \
    "$work/ba/etc/svc/volatile" "$work/ba/etc/dfs" "$work/ba/var/run" "$work/ba/usr"
: >"$work/ba/etc/mnttab"
: >"$work/ba/etc/dfs/sharetab"

# /sbin/init: main() -> start_init() -> exec_init() execs zone_initname, which
# is "/sbin/init" (uts/common/os/main.c:140).
install -Dm755 "$init/sbin/init" "$work/ba/sbin/init"

# The flags here are not cosmetic; each one is load-bearing.
#
# -R  Rock Ridge. krtld's standalone reader (common/fs/hsfs.c, which parses
#     SUSP/RRIP) uses it, so every module loaded *before* the root mount is
#     found by its real lowercase name.
# -D  do not relocate directories deeper than iso9660's eight-level limit,
#     which platform/i86pc/kernel/drv/amd64/<drv> is right up against.
#
# After the root mount, though, Rock Ridge is *off*: hsfs_mountroot() calls
# hs_mountfs() with mount_flags = 1, and 1 is HSFSMNT_NORRIP
# (uts/common/sys/fs/hsfs_rrip.h:41). So a root hsfs is always read as plain
# iso9660, and every post-root modload() sees the ISO names, not the RR ones.
# hs_dirlook() (uts/common/fs/hsfs/hsfs_node.c) upper-cases the name it is
# given before comparing, so "kernel" finds "KERNEL" and directories are fine
# -- but the default ISO rendering of a file is "CTFS.;1", with a trailing
# period and a version suffix, and "CTFS" does not match that. Hence:
#
# -d           omit the trailing period from names that have no extension
# -N           omit the ";1" version suffix
# -iso-level 2 allow names longer than 8.3, for driver_aliases,
#              name_to_sysnum, pci_autoconfig and friends
#
# Without those three the root mounts, the directory walk works, and then
# every single module load fails with ENOENT -- which reads like a broken
# filesystem and is really just filename translation.
"$xorriso/bin/xorrisofs" -R -D -d -N -iso-level 2 \
    -o "$work/iso/platform/i86pc/boot_archive" \
    "$work/ba" >"$work/mkarchive.log" 2>&1

cp "$unix/platform/i86pc/kernel/amd64/unix" "$work/iso/platform/i86pc/kernel/amd64/"

cat >"$work/iso/boot/grub/grub.cfg" <<'EOF'
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=1
set default=0
menuentry "illumos" {
    multiboot /platform/i86pc/kernel/amd64/unix /platform/i86pc/kernel/amd64/unix -B console=ttya,input-console=ttya,fstype=hsfs
    module /platform/i86pc/boot_archive type=rootfs
    boot
}
EOF

PATH="$grub/bin:$xorriso/bin:$PATH" \
    grub-mkrescue -o "$work/illumos.iso" "$work/iso" >"$work/mkrescue.log" 2>&1

echo "=== booting $work/illumos.iso (^A x to quit) ==="
exec "$qemu" \
    -display none -no-reboot -m 4096 \
    -cdrom "$work/illumos.iso" \
    -serial mon:stdio
