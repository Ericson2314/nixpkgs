{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnvpair,
  # libnvpair.so.1 serialises with XDR and so carries libnsl, which in turn
  # carries libmd/libmp; the illumos link-editor insists on finding a shared
  # object's own dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libzfs_core.so.1 -- the *stable* ZFS ioctl interface. Every entry point
# (`lzc_create`, `lzc_snapshot`, `lzc_send`, `lzc_hold`, ...) is a thin
# nvlist-in/nvlist-out wrapper around one `ioctl()` on /dev/zfs, with no
# caching, no name parsing and no policy. That is the whole design: libzfs is
# where the history and the heuristics live, and it was split so that other
# consumers would have something to bind to that does not change under them.
#
# It links only `-lc -lnvpair`, since the nvlist is the entire protocol.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libzfs_core/amd64";
  pname = "libzfs_core";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it, with the reason in a comment: mount(8) needs
    # this library, so it has to be in / rather than /usr.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libzfs_core"

    # Makefile.com's INCS name both of these directly:
    # `-I../../../uts/common/fs/zfs` for the private on-disk and ioctl
    # declarations (<sys/zfs_ioctl.h> and what it includes), and
    # `-I../../../common/zfs` for the shared name/property tables.
    "usr/src/uts/common/fs/zfs"
    "usr/src/common/zfs"

    # `-I../../libc/inc` is on the include path too; only the headers there are
    # wanted, not libc itself.
    "usr/src/lib/libc/inc"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnvpair
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
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libnvpair.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <libzfs_core.h> is the top lib/libzfs_core Makefile's single `HDRS` entry,
  # and that Makefile is the recursive driver we do not run: the amd64
  # subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libzfs_core.so.1 "$out/lib/"
    ln -s libzfs_core.so.1 "$out/lib/libzfs_core.so"

    mkdir -p "$dev/include"
    cp ../common/libzfs_core.h "$dev/include/"

    runHook postInstall
  '';
}
