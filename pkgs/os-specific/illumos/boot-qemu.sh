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
# consconfig() completes with a working console, main() forks init, init runs,
# and init prints. The whole thing ends like this, and the script exits 0 in
# about 15 seconds rather than sitting at a prompt:
#
#     strplumb: failed to initialize drv/dld
#     NOTICE: MPO disabled because memory is interleaved
#
#
#     *** HELLO FROM USERLAND: cross-built illumos init is running ***
#     syncing file systems... done
#
# The last line is the uadmin() shutdown path, reachable only from user mode:
# `illumos.init-stub` ends in uadmin(A_SHUTDOWN, AD_POWEROFF), so the machine
# powers itself off and qemu exits. Two other checks agree, both independent of
# the console: an init that is nothing but an infinite userland `nop` loop
# parks every sampled register at RIP=0x40007c with CPL=3, and the poweroff
# timing is unmistakable against the harness timeout.
#
# Note that init does *not* print via /dev/console, and cannot:
#
#   * /dev/console does not exist. devfsadm(8) creates it, and there is no
#     userland to run devfsadm. It cannot be baked into the boot image either,
#     for two independent reasons: /dev is a mount point -- vfs_mountdev1()
#     (common/fs/vfs.c:767) mounts the `dev` filesystem over it -- so anything
#     underneath is shadowed; and a root hsfs is read as plain iso9660 (see
#     below), which cannot represent a symlink at all.
#   * /devices/pseudo/iwscn@0:iwscn opens and its writes return the full byte
#     count, but nothing comes out. With console=ttya this is the CONSOLE_TIP
#     case in consconfig_dacf.c -- stdin is not a keyboard and is the same
#     device as stdout -- and there `rconsvp` is the serial device itself, not
#     the indirect console. iwscn redirects to the workstation console, which
#     has no framebuffer under it here, so it discards.
#
# So init walks a list of candidates and writes to each one that opens; the one
# that actually reaches the port is the device node,
# /devices/pci@0,0/isa@1/asy@1,3f8:a on qemu's default i440fx. That is
# chipset-specific, which is the honest reason devfsadm exists. Packaging it
# (libdevinfo, libdevice, the link-generator modules) is the real fix.
#
# (Two historical notes, because both cost real time and both are the kind of
# failure that looks like something else.
#
# Until the PCI nexus drivers below were packaged, *all* console output stopped
# dead at consconfig() -- on serial and on VGA alike, checked by screendumping
# the VGA text console through the qemu monitor during a serial-console boot.
# The mechanism: console_putchar() falls back to prom_putchar() until a user
# process holds the console stream, prom_putchar() goes through `sysp`, and
# consconfig_init_input() repoints `sysp` at kern_sysp
# (common/io/consconfig_dacf.c:1499), whose sysp_putchar/sysp_ischar route to
# cons_polledio -- and with no serial port in the device tree there was no
# polled console to route to. It presented as a hang, and it was not one.
#
# And before exec/elfexec was packaged, that same silence hid an exec failure.
# The kernel was busy-looping in sysp_ischar() from prom_getchar(), reached
# from prom_reboot_prompt() via prom_exit_to_mon() from halt("unix: Could not
# start init"). That was pinned down by attaching gdb to the qemu gdbstub --
# `target remote :1234` with $unix/platform/i86pc/kernel/amd64/unix as the
# symbol file -- where the backtrace showed prom_reboot_prompt on a
# thread_start stack, i.e. the init thread rather than main()'s, which pointed
# at init rather than at the console. Temporarily stubbing prom_io_use_kernel()
# to a no-op then let the kernel say it outright: "WARNING: exec(/sbin/init)
# failed with errno 8". Both tricks are worth remembering.)
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
libc=$(build pkgsCross.x86_64-illumos.illumos.libc)

# ILLUMOS_INIT=stub (the default) boots the freestanding init that prints one
# line and powers the machine off, so this script finishes on its own in about
# fifteen seconds. ILLUMOS_INIT=shell puts an interactive bash on the console
# instead, in which case the script does *not* finish -- leave with `^A x`.
case ${ILLUMOS_INIT:-stub} in
stub)
    init=$(build pkgsCross.x86_64-illumos.illumos.init-stub)
    closure=
    ;;
shell)
    init=$(build pkgsCross.x86_64-illumos.illumos.init-shell)
    # bash is an ordinary dynamically linked illumos program, so its whole
    # NEEDED closure has to be in the archive: readline, history, ncursesw,
    # socket, nsl and the libc composite -- which is also where ld.so.1 and
    # the sgs libraries ld.so.1 itself needs come from.
    closure="$(build pkgsCross.x86_64-illumos.bashInteractive) $libc"
    ;;
*)
    echo "$0: ILLUMOS_INIT must be 'stub' or 'shell', not '$ILLUMOS_INIT'" >&2
    exit 1
    ;;
esac

# Extra userland to put in the image, on top of whatever init needs.
#
#   ILLUMOS_EXTRA    space-separated nix attribute paths. Each one's runtime
#                    closure is staged at its real store path, exactly as the
#                    shell's is, so a program cross-built here can just be run
#                    by absolute path.
#   ILLUMOS_PAYLOAD  a host directory, copied to /payload in the image, for
#                    test inputs that are not nix packages.
#
# Both only do anything with ILLUMOS_INIT=shell, since the stub init runs
# nothing else. Because `-serial mon:stdio` hands the guest shell this
# script's own stdin, that combination is enough to run a real command on the
# cross-built userland non-interactively and read its output back:
#
#     ILLUMOS_INIT=shell \
#     ILLUMOS_EXTRA=pkgsCross.x86_64-illumos.illumos.svccfg \
#     ILLUMOS_PAYLOAD=/tmp/manifests \
#     ./boot-qemu.sh <<'EOF'
#     "$svccfg/bin/svccfg" validate /payload/sysctl.xml
#     EOF
for attr in ${ILLUMOS_EXTRA:-}; do
    closure="$closure $(build "$attr")"
done

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
# --preserve=mode, because with Rock Ridge the image carries real permissions
# and anything that has to be exec'd needs its mode bit to survive the copy.
# The store is read-only, so make the staging tree writable again afterwards.
cp -RL --preserve=mode "$unix/kernel" "$unix/platform" "$unix/usr" "$work/ba/"
chmod -R u+w "$work/ba/kernel" "$work/ba/platform" "$work/ba/usr"
cp "$src/uts/intel/os/name_to_sysnum" "$src/uts/intel/os/minor_perm" \
   "$src/uts/intel/os/dacf.conf" "$work/ba/etc/"
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
npe "pciex_root_complex"
pcieb "pciexclass,060400"
pcieb "pciexclass,060401"
pseudo "zconsnex"
EOF

# /etc/driver_classes is the third file add_drv(8) owns, and the copy in the
# gate (uts/intel/os/driver_classes) is a zero-byte placeholder. Two entries
# matter, both from `class=` attributes in the manifests rather than aliases:
# `pci` (system-kernel-platform.p5m:190) and `isa` (:188). read_class_file()
# in uts/common/os/modsysfile.c parses this as "<driver> <class>" pairs.
cat >"$work/ba/etc/driver_classes" <<'EOF'
pci	pci
isa	sysbus
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

# See ILLUMOS_PAYLOAD above. Dereferenced (`-L`), because the usual thing to
# point it at is a directory of symlinks into the store, and those targets are
# not otherwise staged.
if [ -n "${ILLUMOS_PAYLOAD:-}" ]; then
    mkdir -p "$work/ba/payload"
    cp -RL --preserve=mode "$ILLUMOS_PAYLOAD"/. "$work/ba/payload/"
    chmod -R u+w "$work/ba/payload"
fi

if [ -n "$closure" ]; then
    # Stage the store paths init needs, at their real locations, because
    # PT_INTERP and DT_RUNPATH are absolute store paths. `cp -a` rather than
    # `cp -RL`: with Rock Ridge the image can hold symlinks, so the closure
    # stays a symlink farm instead of every link becoming a full copy of its
    # target. (Before Rock Ridge that alone roughly doubled the archive.)
    for p in $(nix-store -qR $closure); do
        mkdir -p "$work/ba$(dirname "$p")"
        cp -a "$p" "$work/ba$p"
    done
    chmod -R u+w "$work/ba/nix"

    # A real illumos root keeps its 64-bit libraries in /lib/amd64, with
    # /lib/64 as the alias. Two things need this and neither uses a runpath:
    # ld.so.1's SONAME is the absolute string "/lib/amd64/ld.so.1", and
    # libraries like libnsl.so.1 carry no DT_RUNPATH at all and rely on the
    # default /lib/64 search path.
    mkdir -p "$work/ba/lib/amd64"
    ln -sfn amd64 "$work/ba/lib/64"
    for f in "$libc"/lib/*.so.*; do
        [ -e "$f" ] || continue
        ln -sfn "$f" "$work/ba/lib/amd64/$(basename "$f")"
    done
    ln -sfn "$libc/lib/amd64/ld.so.1" "$work/ba/lib/amd64/ld.so.1"
fi

# -R  Rock Ridge: real names, POSIX modes and ownership, and symbolic links.
#     Both readers use it -- krtld's standalone one (common/fs/hsfs.c) for
#     everything loaded before the root mount, and the hsfs module afterwards.
# -D  do not relocate directories deeper than iso9660's eight-level limit,
#     which platform/i86pc/kernel/drv/amd64/<drv> is right up against.
#
# Rock Ridge on the *root* needs the `uts: mount the root hsfs with Rock Ridge`
# patch: hsfs_mountroot() otherwise calls hs_mountfs() with mount_flags = 1,
# which is HSFSMNT_NORRIP (uts/common/sys/fs/hsfs_rrip.h:41), so a root hsfs is
# read as plain iso9660 no matter what the medium carries. Without that patch
# this needs `-d -N -iso-level 4` instead, because plain iso9660 renders a file
# called `ctfs` as `CTFS.;1` and caps names well below the ~50 characters a nix
# store directory needs -- and even then there are no symlinks and no modes, so
# every symlink has to be materialised as a full copy of its target. That cost
# the boot archive about half its size before this patch landed.
"$xorriso/bin/xorrisofs" -R -D \
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
