{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libdevinfo,
  libadm,
  libdevid,
  libkstat,
  libsysevent,
  libnvpair,
  libefi,
  libfdisk,
  # <libzfs.h>, for the header only: `inuse_zpool.c` asks libzfs whether a
  # slice is already part of a pool, and reaches it through `dlopen` rather
  # than a link -- Makefile.com carries no `-lzfs`. Which is what keeps this
  # from being a cycle, since `zpool` links both.
  libzfs,
  # ...and <libzfs.h> includes <libzfs_core.h> and <libnvpair.h>, so their
  # headers have to be on the path too.
  libzfs_core,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's own dependencies on the link path. libefi
  # brings libuuid's dlpi/dladm cluster (see libefi.nix), libdevinfo brings the
  # libsec/libidmap/libuutil/libgen cluster.
  libuuid,
  libsmbios,
  libsocket,
  libnsl,
  libdlpi,
  libdladm,
  libinetutil,
  libscf,
  librcm,
  libexacct,
  libpool,
  libvarpd,
  libgen,
  libuutil,
  libsec,
  libavl,
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
    libdevinfo
    libadm
    libdevid
    libkstat
    libsysevent
    libnvpair
    libefi
    libfdisk
    libuuid
    libsmbios
    libsocket
    libnsl
    libdlpi
    libdladm
    libinetutil
    libscf
    librcm
    libexacct
    libpool
    libvarpd
    libgen
    libuutil
    libsec
    libavl
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

# libdiskmgt.so.1 -- "is this disk in use, and by what?". It walks the device
# tree with libdevinfo (findevs.c), then for each slice asks a series of
# `inuse_*` questions: is it a mounted filesystem, a dump device, a swap
# device, a Veritas volume, or already part of a ZFS pool (inuse_zpool.c).
#
# `zpool` links it for exactly that. `zpool create` calling
# `check_disk`/`check_device` in zpool_vdev.c is how you get
#
#     /dev/dsk/c1t0d0s0 is currently mounted on /export. Please see umount(8).
#
# rather than a cheerfully destroyed filesystem. That check is what `-f`
# overrides.
#
# On x86 its Makefile.com adds `i386_LDLIBS = -lfdisk`, since the partition
# scan has to read an MBR before it can find a Solaris partition to read
# slices out of.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdiskmgt/amd64";
  pname = "libdiskmgt";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/libdiskmgt"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libdevinfo
    libadm
    libdevid
    libkstat
    libsysevent
    libnvpair
    libefi
    libfdisk
    libzfs
    libzfs_core
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
  # from the closure.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libdevinfo.dev}/include -I${libdevid.dev}/include -I${libkstat.dev}/include -I${libsysevent.dev}/include -I${libnvpair.dev}/include -I${libfdisk.dev}/include -I${libadm.dev}/include -I${libzfs.dev}/include -I${libzfs_core.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # <libdiskmgt.h> is the top lib/libdiskmgt Makefile's single `HDRS` entry,
  # and that Makefile is the recursive driver we do not run: the amd64
  # subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdiskmgt.so.1 "$out/lib/"
    ln -s libdiskmgt.so.1 "$out/lib/libdiskmgt.so"

    mkdir -p "$dev/include"
    cp ../common/libdiskmgt.h "$dev/include/"

    runHook postInstall
  '';
}
