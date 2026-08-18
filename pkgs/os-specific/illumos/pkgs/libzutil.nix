{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libm,
  libdevid,
  libnvpair,
  libadm,
  libavl,
  libefi,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's own dependencies on the link path. libefi
  # brings libuuid's whole dlpi/dladm cluster (see libefi.nix), and libdevid
  # brings libdevinfo's.
  libuuid,
  libsmbios,
  libsocket,
  libnsl,
  libdlpi,
  libdladm,
  libinetutil,
  libdevinfo,
  libscf,
  librcm,
  libexacct,
  libkstat,
  libpool,
  libvarpd,
  libgen,
  libuutil,
  libsec,
  libidmap,
  libumem,
  libidspace,
  librename,
  libxml2,
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libm
    libdevid
    libnvpair
    libadm
    libavl
    libefi
    libuuid
    libsmbios
    libsocket
    libnsl
    libdlpi
    libdladm
    libinetutil
    libdevinfo
    libscf
    librcm
    libexacct
    libkstat
    libpool
    libvarpd
    libgen
    libuutil
    libsec
    libidmap
    libumem
    libidspace
    librename
    libxml2.out
    libmd
    libmp
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libzutil.so.1 -- the part of libzfs that has nothing to do with a live pool:
# the device-scanning importer (`zpool_search_import`, zutil_import.c, which
# walks /dev/dsk reading vdev labels and reassembles configurations from them),
# `zfs_nicenum` and friends, and the pool-name/property helpers shared with
# libzpool.
#
# The split exists so that `libzpool` -- the userland build of the ZFS core,
# used by zdb and ztest -- can have the scanning code without pulling in
# libzfs, which is the /dev/zfs ioctl client. Both link it.
#
# The `-ladm -lefi` here are the label readers: an import scan has to be able
# to read an SMI VTOC and a GPT to know which slice of a disk to look at.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libzutil/amd64";
  pname = "libzutil";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it, with the reason in a comment: mount(8) needs
    # this library, so it has to be in / rather than /usr.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libzutil"

    # Makefile.com's INCS: `-I../../../uts/common/fs/zfs` for the private
    # on-disk declarations (<sys/vdev_impl.h>, <sys/zfs_ioctl.h>), and
    # `-I../../libc/inc` for libc's private headers.
    "usr/src/uts/common/fs/zfs"
    "usr/src/lib/libc/inc"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libm
    libdevid
    libnvpair
    libadm
    libavl
    libefi
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. Every `-L` gets a matching `-R`: without it
  # there is no DT_RUNPATH and no nix reference, so the dependency is absent
  # from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libnvpair.dev}/include -I${libdevid.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # <libzutil.h> is the top lib/libzutil Makefile's single `HDRS` entry, and
  # that Makefile is the recursive driver we do not run: the amd64
  # subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libzutil.so.1 "$out/lib/"
    ln -s libzutil.so.1 "$out/lib/libzutil.so"

    mkdir -p "$dev/include"
    cp ../common/libzutil.h "$dev/include/"

    runHook postInstall
  '';
}
