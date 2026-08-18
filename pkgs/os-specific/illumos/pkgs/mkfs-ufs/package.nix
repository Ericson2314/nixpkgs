{
  lib,
  mkDerivation,

  libcompat,
}:

# mkfs_ufs(8), so that a UFS root filesystem image can be made without an
# illumos machine to make it on.
#
# It is consumed for the *build host* -- but that is the consumer's business,
# not this file's. Listing it in `nativeBuildInputs` gets the build-platform
# instance out of the scope's splicing, exactly as for every other package
# here, and that instance's plain `$CC` is the build compiler. This file used
# to say so itself with `noCC` + `depsBuildBuild` + `$CC_FOR_BUILD`, which
# hand-rolled machinery the scope already had -- and made `illumos.mkfs-ufs`
# yield a build-host binary even when the cross instance was asked for.
#
# Why this rather than FreeBSD's makefs: illumos' UFS is not 4.4BSD FFS on
# disk. `struct direct` here carries a 16-bit `d_namlen` where FFS puts a
# `d_type` byte followed by an 8-bit namlen, so a directory written by makefs
# is misread by illumos and vice versa. Using the gate's own mkfs removes that
# entire class of question: whatever it writes is by construction what illumos
# reads.
#
# This is not a port in the sense of a fork. The gate source needed five
# changes to build and run here, and all five are on the `nix-cross` branch as
# ordinary commits (see ../patches/002[1-5]-mkfs-*): four are portability fixes
# that are just as correct on illumos -- a `true:` label that C23 rejects, two
# K&R declarations, one genuine pointer-type mismatch -- and the fifth teaches
# mkfs to target a regular file rather than only a disk, which is a feature
# illumos gains too. Nothing about a foreign libc leaked into them; that is all
# in `libcompat`.
#
# Deliberately built with the "gate" compat profile: mkfs needs illumos' real
# <sys/fs/ufs_fs.h> and everything under it, which is nothing like the staged
# ELF header subset the onbld tools use. See libcompat.nix.
mkDerivation {
  pname = "mkfs-ufs";

  path = "usr/src/cmd/fs.d/ufs/mkfs";
  extraPaths = [
    # roll_log.c is compiled in, not linked from a library.
    "usr/src/cmd/fs.d/ufs/roll_log"
    "usr/src/cmd/fs.d/fslib.h"

    # Not used to build anything -- the compilation below is direct. The setup
    # hook probes for an `install_h` target with `make -Pp` before installing,
    # and that probe has to be able to read this component's Makefile and
    # everything it includes. Without these it still succeeds, but only after
    # printing a make fatal error, which reads like a real failure.
    "usr/src/cmd/fs.d/ufs/Makefile.roll"
    "usr/src/cmd/fs.d/Makefile.fstype"
    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.targ"
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    # The gate's own headers, which win over the host's throughout. `head` is
    # the userland set; the three uts trees supply <sys/*> -- including the
    # on-disk UFS layout, which is the whole point.
    "usr/src/head"
    "usr/src/uts/common"
    "usr/src/uts/intel"
    "usr/src/uts/i86pc"
  ];

  # The gate's makefile here drives dmake and the full illumos toolchain, and
  # would build a target binary. This is three translation units plus compat,
  # so compile them directly rather than teaching that makefile about a foreign
  # host.
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # $SRC is usr/src, exported by the illumos setup hook; the working
    # directory is $COMPONENT_PATH, which the same hook cd'd into.

    # Order matters: the compat overlay must precede the gate's own headers so
    # that its <sys/stat.h> and <iso/stdio_iso.h> are found first. Each of
    # those includes the gate's version and then repoints just the one thing
    # that cannot survive meeting a foreign libc.
    gateFlags="${libcompat.overlayCflags} \
      -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 \
      -I$SRC/head -I$SRC/uts/common -I$SRC/uts/intel -I$SRC/uts/i86pc \
      -I$SRC/cmd/fs.d -I$SRC/cmd/fs.d/ufs/roll_log"

    for f in \
      "$SRC/cmd/fs.d/ufs/mkfs/mkfs.c" \
      "$SRC/cmd/fs.d/ufs/mkfs/populate.c" \
      "$SRC/cmd/fs.d/ufs/roll_log/roll_log.c"
    do
      echo "compiling (gate headers) $f"
      $CC -c -o "$(basename "$f" .c).o" -I${libcompat.srcDir} $gateFlags "$f"
    done

    # compat_gate.c is the gate-side half of the shims mkfs_ufs needs, and
    # mkfs_ufs is still its only consumer -- but it lives in the gate tree
    # beside compat_host.c, the half it calls into, and `compat` hands both
    # out. Splitting the two halves of one interface across two repositories
    # only made compat_priv.h harder to keep honest.
    #
    # Compiled on its own rather than in the loop above because the loop names
    # its object after `basename`, and a store path basename carries the hash
    # prefix -- `-o` here is explicit for that reason.
    echo "compiling (gate headers) ${libcompat.gateSource}"
    $CC -c -o compat_gate.o -I${libcompat.srcDir} $gateFlags "${libcompat.gateSource}"

    # The host half sees the *host's* headers only -- that is the whole reason
    # it is a separate translation unit -- so it gets none of the flags above.
    echo "compiling (host headers) ${libcompat.hostSource}"
    $CC -c -o compat_host.o -D_GNU_SOURCE -D_LARGEFILE64_SOURCE \
      -I${libcompat.srcDir} "${libcompat.hostSource}"

    $CC -o mkfs_ufs mkfs.o populate.o roll_log.o compat_gate.o \
      compat_host.o

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    # Not `install -D`: illumos' own install(1) is on PATH here (mkDerivation
    # puts it there for the gate makefiles) and does not take -D.
    mkdir -p $out/bin
    cp mkfs_ufs $out/bin/mkfs_ufs
    chmod 755 $out/bin/mkfs_ufs
    runHook postInstall
  '';

  # A smoke test that is worth the seconds it costs: make a small filesystem in
  # a file and check that the superblock mkfs says it wrote is really there.
  # `FS_MAGIC` is 0x011954 at offset 1372 of the superblock, and the superblock
  # starts at sector 32 -- so byte 16384 + 1372. Getting this far means the
  # geometry maths, the aio write path and the compat stat translation all
  # worked; a wrong `struct stat` used to smash the stack well before here.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    truncate -s 64M smoke.img
    $out/bin/mkfs_ufs -F ufs smoke.img 131072

    magic=$(od -A n -t x4 -j $((16384 + 1372)) -N 4 smoke.img | tr -d ' \n')
    if [ "$magic" != "00011954" ]; then
      echo "no UFS superblock in the image: got '$magic', wanted 00011954" >&2
      exit 1
    fi
    echo "UFS superblock magic verified"

    # And that `-R` really fills one in. The tree is small but deliberately
    # covers the cases that broke while this was being written: a file large
    # enough to need an indirect block, enough names in one directory to span
    # several DIRBLKSIZ chunks (an off-by-one there silently redirected the
    # first name of each following chunk to the wrong inode), a symlink, and a
    # hard link.
    mkdir -p tree/sub
    head -c 200000 /dev/urandom > tree/big.bin
    for i in $(seq 1 60); do echo "contents of file $i" > "tree/sub/f$i.txt"; done
    echo payload > tree/target
    ln -s ../target tree/sub/link
    ln tree/target tree/alias

    truncate -s 64M pop.img
    $out/bin/mkfs_ufs -F ufs -R tree pop.img 131072

    # There is no UFS reader on the build host to walk the result with, so
    # check it differentially instead: names and contents that appear in the
    # populated image must be absent from the empty one made moments earlier
    # from the same mkfs. That covers directory entries (the name), file data
    # (the payload) and symlink targets, without depending on any struct
    # offset -- an offset this check got wrong once already, silently reading
    # zero from both images and "passing".
    for needle in f42.txt payload ../target big.bin; do
      if ! grep -qaF -- "$needle" pop.img; then
        echo "populated image does not contain '$needle'" >&2
        exit 1
      fi
      if grep -qaF -- "$needle" smoke.img; then
        echo "empty image already contains '$needle'; the check proves nothing" >&2
        exit 1
      fi
    done
    echo "populate wrote directory names, file contents and symlink targets"

    runHook postInstallCheck
  '';

  meta = {
    description = "illumos UFS mkfs, built to run on the build host";
    mainProgram = "mkfs_ufs";
    platforms = lib.platforms.unix;
  };
}
