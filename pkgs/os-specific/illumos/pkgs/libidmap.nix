{
  buildPackages,
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
  libscf-headers,
  libavl,
  libuutil,
  libnsl,
  libnvpair,
  # libnsl.so.1 pulls in libmp/libmd, and the illumos link-editor insists on
  # finding a shared object's own dependencies on the link path.
  libmd,
  libmp,
}:

# libidmap.so.1 -- the client side of the SMB/NFSv4 identity mapping service.
# It translates between POSIX uid/gid and Windows SIDs by making door and RPC
# calls to `idmapd`, and it is what turns an on-disk NFSv4 ACL entry naming a
# SID into something `getpwuid` can be asked about.
#
# It is here only as a transitive dependency: `libsec.so.1` links `-lidmap`
# (`lib/libsec/Makefile.com:47`) for the `idmap_getwinnamebyuid` /
# `idmap_getuidbywinname` calls in `common/aclutils.c`'s name<->id conversion,
# and the illumos link-editor requires a shared object's own dependencies to
# be findable on the link path of anything that links against it.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libidmap/amd64";
  pname = "libidmap";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/libidmap"

    # `Makefile.com`'s IDMAP_PROT_X is a *relative* path into the kernel tree
    # -- deliberately so, per the comment there, since rpcgen bakes the path it
    # was given into the `#include` it emits.
    "usr/src/uts/common/rpcsvc"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [
    buildPackages.netbsd.rpcgen
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libscf-headers
    libuutil
    # <rpcsvc/idmap_prot.h> includes <libnvpair.h>: the idmap protocol carries
    # its extensible attributes as a packed nvlist.
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  # Same story as libnsl: NetBSD's rpcgen shells out to a C preprocessor and
  # defaults to a /usr/bin path that does not exist here. It has to be a
  # *traditional* cpp so that `%`-escaped lines pass through without
  # `__STDC__` being expanded inside them.
  env.RPCGEN_CPP = buildPackages.writeShellScript "rpcgen-cpp" ''
    exec ${buildPackages.stdenv.cc}/bin/cpp -traditional-cpp -U__STDC__ "$@"
  '';

  buildFlags = [ "all" ];

  # illumos' rpcgen writes the `#include` for the protocol header by taking the
  # path it was handed and swapping `.x` for `.h` -- which is precisely why
  # `Makefile.com` spells IDMAP_PROT_X relatively, so that the emitted include
  # is `"../../../uts/common/rpcsvc/idmap_prot.h"`. NetBSD's rpcgen emits the
  # *basename* instead (`#include "idmap_prot.h"`), and the generated
  # `idmap_xdr.c` then cannot find it. Put the directory holding the installed
  # `rpcsvc/idmap_prot.h` on the include path so the bare name resolves.
  #
  # It goes through `makeFlagsArray` rather than `makeFlags` because it
  # contains a space, and `makeFlags` entries are word-split.

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${headers}/include/rpcsvc")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libavl}/lib -L${libuutil}/lib -L${libnsl}/lib -L${libnvpair}/lib -L${libmd}/lib -L${libmp}/lib \$(LDLIBS)")
  '';

  # <idmap.h> and the private <idmap_priv.h>/<idmap_impl.h> are installed into
  # /usr/include by the *top* lib/libidmap Makefile, which we do not run: we
  # build the amd64 subdirectory directly. libsec includes <idmap.h>, so ship
  # the header set from the source directory instead.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libidmap.so.1 "$out/lib/"
    ln -s libidmap.so.1 "$out/lib/libidmap.so"

    mkdir -p "$dev/include"
    cp ../common/idmap.h ../common/idmap_priv.h ../common/idmap_impl.h \
      ../common/idmap_cache.h ../common/directory.h "$dev/include/"

    runHook postInstall
  '';
}
