{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libm,
  libdevid,
  libgen,
  libnvpair,
  libuutil,
  libavl,
  libefi,
  libidmap,
  libtsol,
  libcryptoutil,
  libpkcs11,
  libmd,
  libumem,
  libzfs_core,
  libdevinfo,
  libzutil,
  zlib,
  pkcs11-headers,
  libshare-headers,
  libtopo-headers,
  # <libcmdutils.h>, for `nicenum` and the extended-attribute helpers. libzfs
  # includes it but does not link it -- the entry points it uses are inline or
  # come in through libc -- so only the `dev` output is wanted.
  libcmdutils,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's own dependencies on the link path. libefi
  # brings libuuid's dlpi/dladm cluster (see libefi.nix), libdevinfo the
  # libsec/libgen one, and libtsol brings libsecdb.
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
  libkstat,
  libpool,
  libvarpd,
  libsec,
  libsecdb,
  libidspace,
  librename,
  libxml2,
  libmp,
  libadm,
}:

let
  runtimeLibs = [
    libm
    libdevid
    libgen
    libnvpair
    libuutil
    libavl
    libefi
    libidmap
    libtsol
    libcryptoutil
    libpkcs11
    libmd
    libumem
    libzfs_core
    libdevinfo
    libzutil
    libadm
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
    libkstat
    libpool
    libvarpd
    libsec
    libsecdb
    libidspace
    librename
    libxml2.out
    libmp
    zlib
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libzfs.so.1 -- the library `zfs`(8) and `zpool`(8) are written against, and
# the one that carries all the policy. Where `libzfs_core` is one ioctl per
# call and nothing else, libzfs is where dataset and pool *handles* live, where
# property tables are interpreted, where `zpool create` decides how to label a
# disk, where mounting and sharing a dataset is driven, and where an error
# number becomes a sentence.
#
# The dependency list is long because each entry is one of those jobs:
#
#   -lefi -ladm    labelling a whole disk (`zpool_label_disk`) and reading back
#                  what is already on it.
#   -lzutil        the import scanner, shared with libzpool.
#   -lidmap -ltsol the SID and label sides of the NFSv4-style ACLs ZFS stores.
#   -lcryptoutil   } SHA-256 through the Cryptographic Framework rather than a
#   -lpkcs11       } private implementation.
#   -lz            `zfs send -c`-adjacent compression of the stream metadata.
#   -lumem -lavl -luutil -lnvpair
#                  the usual illumos runtime, plus the nvlist that *is* the
#                  ioctl protocol.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libzfs/amd64";
  pname = "libzfs";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it, with the reason in a comment: mount(8) needs
    # this library, so it has to be in / rather than /usr.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libzfs"

    # OBJS_SHARED is compiled straight out of the code shared with the kernel
    # -- the property tables, the fletcher checksums, the name checker -- via
    # Makefile.com's own `pics/%.o: ../../../common/zfs/%.c` rule.
    "usr/src/common/zfs"

    # Makefile.com's INCS: the private on-disk and ioctl declarations, libc's
    # private headers, and libzutil's public one (which arrives through its
    # `dev` output as well; the `-I` here is what upstream's proto area would
    # have supplied).
    "usr/src/uts/common/fs/zfs"
    "usr/src/lib/libc/inc"
    "usr/src/lib/libzutil/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libm
    libdevid
    libgen
    libnvpair
    libuutil
    libavl
    libefi
    libidmap
    libtsol
    libcryptoutil
    libpkcs11
    pkcs11-headers
    libmd
    libumem
    libzfs_core
    libdevinfo
    libzutil
    zlib
    libshare-headers
    libtopo-headers
    libcmdutils
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
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libnvpair.dev}/include -I${libuutil.dev}/include -I${libdevid.dev}/include -I${libdevinfo.dev}/include -I${libidmap.dev}/include -I${libtsol.dev}/include -I${libsec.dev}/include -I${libumem.dev}/include -I${libcryptoutil.dev}/include -I${pkcs11-headers}/include -I${libzfs_core.dev}/include -I${libzutil.dev}/include -I${zlib.dev}/include -I${libshare-headers}/include -I${libtopo-headers}/include -I${libcmdutils.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # <libzfs.h> is the top lib/libzfs Makefile's single `HDRS` entry, and that
  # Makefile is the recursive driver we do not run: the amd64 subdirectory is
  # built directly. `common/sys` goes with it -- <libzfs.h> includes
  # <sys/fs/zfs.h> from there.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libzfs.so.1 "$out/lib/"
    ln -s libzfs.so.1 "$out/lib/libzfs.so"

    mkdir -p "$dev/include"
    cp ../common/libzfs.h ../common/libzfs_impl.h "$dev/include/"
    cp -r ../common/sys "$dev/include/" 2>/dev/null || true

    runHook postInstall
  '';
}
