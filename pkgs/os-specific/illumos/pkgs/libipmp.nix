{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libinetutil,
  libsocket,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libipmp.so.1 -- the client side of IPMP, IP network multipathing. It is a
# door/socket client of `in.mpathd`: `ipmp_open`/`ipmp_snap` ask the daemon
# for the current group, interface and target state, and the admin entry
# points hand it offline/undo requests.
#
# Packaged because `ifconfig` and `ipadm` both link it -- every IPMP group
# operation and the `ipmpstat`-style reporting in those commands is a query
# through here -- and those commands are how a nix-built illumos will plumb
# its loopback and NIC.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libipmp/amd64";
  pname = "libipmp";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: ifconfig lives in /sbin, so libipmp goes to
    # /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libipmp"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libinetutil
    libsocket
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # `ipmp_query.c` includes <libinetutil.h> for the interface-name helpers, so
  # libinetutil's `dev` output has to be on the include path explicitly:
  # CPPFLAGS.first is searched before the -I../common that Makefile.com adds
  # for libipmp's own headers.
  #
  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. Every `-L` gets a matching `-R`: without it
  # there is no DT_RUNPATH and no nix reference, so the dependency is absent
  # from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libinetutil.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libinetutil}/lib -R${libinetutil}/lib -L${libsocket}/lib -R${libsocket}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # The five headers below are the *top* lib/libipmp Makefile's `HDRS`, which
  # we do not run: the amd64 subdirectory is built directly.
  # `ipmp_query_impl.h` is in that list despite the `_impl` name -- `ipmpstat`
  # and in.mpathd share the snapshot layout it declares.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libipmp.so.1 "$out/lib/"
    ln -s libipmp.so.1 "$out/lib/libipmp.so"

    mkdir -p "$dev/include"
    cp ../common/ipmp.h ../common/ipmp_admin.h ../common/ipmp_mpathd.h \
      ../common/ipmp_query.h ../common/ipmp_query_impl.h "$dev/include/"

    runHook postInstall
  '';
}
