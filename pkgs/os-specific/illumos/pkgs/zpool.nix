{
  mkDerivation,

  headers,

  libzfs,
  libzfs_core,
  libzutil,
  libnvpair,
  libdevid,
  libefi,
  libdiskmgt,
  libuutil,
  libumem,
  libm,
  libcmdutils,
  # <kstat.h>, included by cmd/stat/common/statcommon.h. zpool needs no kstat
  # call itself; the header comes with the shared timestamp code.
  libkstat,
  # `highbit64`/`lowbit64` -- see the note below on `-lzpool`.
  libfakekernel,
}:

# zpool(8) -- create, import, export, scrub and report on storage pools.
#
# Built by hand rather than through cmd/zpool/Makefile, the same way ipadm and
# soconfig are: four .c files, one link. The consequence, as there, is no CTF
# in the binary.
#
# `-lzpool` is deliberately absent from the link, and this is the one real
# departure from upstream's Makefile. libzpool is the *userland build of the
# ZFS core* -- the whole of uts/common/fs/zfs compiled against libfakekernel --
# and it exists for zdb(8) and ztest, which run the DMU in a process. zpool
# does not call into it: every operation it performs goes through libzfs to
# /dev/zfs. Upstream links it anyway, and the link succeeds under `-zdefs`
# without it, which is the check that matters.
#
# The reason to care is that libzpool cannot be built here at all yet: its
# Makefile generates ../common/zfs.h with `dtrace -h` and compiles a DTrace
# provider object into EXTPICS, and dtrace(8) is not packaged. Rather than
# stub that out, note it and link what is actually used. If a future zpool
# subcommand does need libzpool, the link will say so rather than the program
# failing at run time -- `-zdefs` makes an unresolved symbol a build error.
mkDerivation {
  pname = "zpool";
  path = "usr/src/cmd/zpool";

  extraPaths = [
    # `statcommon.h`/`timestamp.c`, which cmd/stat/Makefile.stat adds to
    # $(OBJS): `zpool iostat -T d` prints a timestamp between samples, and the
    # formatting is shared with vmstat(8), iostat(8) and the rest of that
    # family.
    "usr/src/cmd/stat/common"

    # zfs_comutil.c / zfeature_common.c / zfs_prop.h, the property and feature
    # tables shared with the kernel. zpool includes the headers; the code is
    # already inside libzfs.
    "usr/src/common/zfs"

    # <sys/fs/zfs.h> and the private on-disk declarations.
    "usr/src/uts/common/fs/zfs"
  ];

  buildInputs = [
    headers
    libzfs
    libzfs_core
    libzutil
    libnvpair
    libdevid
    libefi
    libdiskmgt
    libuutil
    libumem
    libm
    libcmdutils
    libkstat
    libfakekernel
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    $CC -O2 -o zpool \
      zpool_main.c zpool_vdev.c zpool_iter.c zpool_util.c \
      "$SRC/cmd/stat/common/timestamp.c" \
      -I"$SRC/cmd/stat/common" \
      -I"$SRC/common/zfs" \
      -I"$SRC/uts/common/fs/zfs" \
      -DTEXT_DOMAIN=\"SUNW_OST_OSCMD\" \
      -D_LARGEFILE64_SOURCE=1 -D_REENTRANT \
      -Wno-error \
      -lzfs -lnvpair -ldevid -lefi -ldiskmgt -luutil -lumem -lzutil -lm -lfakekernel

    runHook postBuild
  '';

  # /usr/sbin/zpool is a symlink to ../../sbin/zpool on a real system, because
  # importing the root pool has to work before /usr is mounted. Ship it in
  # `sbin` only; nothing here has a split /usr.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/sbin"
    cp zpool "$out/sbin/zpool"
    chmod 755 "$out/sbin/zpool"

    runHook postInstall
  '';

  meta = {
    description = "illumos ZFS storage pool configuration tool";
    mainProgram = "zpool";
  };
}
