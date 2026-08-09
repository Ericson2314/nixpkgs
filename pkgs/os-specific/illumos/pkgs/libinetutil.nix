{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsocket,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libinetutil.so.1 -- small helpers shared by the networking commands: IP
# address and interface-name parsing (`ifspec`, `ifaddrlist`), the DHCP
# `octet` conversions out of common/net/dhcp, and a little event-handler and
# timer-queue framework (`eh.c`, `tq.c`).
#
# Nothing here is wanted for its own sake yet. It is on the path to
# `svc.configd`: libbsm links `-linetutil`, and svc.configd links `-lbsm` for
# the `adt_*` audit-session calls in its client code.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libinetutil/amd64";
  pname = "libinetutil";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libinetutil"

    # octet.c is not under lib/libinetutil at all: `COMDIR` points at the
    # shared DHCP code, and the amd64 build has an explicit pics rule for it.
    "usr/src/common/net/dhcp"

    # `inetutil.c` includes <libsocket_priv.h>, which reaches upstream builds
    # only through the proto area -- lib/libsocket's Makefile installs it into
    # /usr/include -- so take it from the source directory, exactly as
    # libsocket.nix itself does.
    "usr/src/lib/libsocket/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsocket
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libsocket/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libsocket}/lib -R${libsocket}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <libinetutil.h> is installed into /usr/include by the *top* lib/libinetutil
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  # `libinetutil_impl.h` goes with it because libbsm's consumers reach for the
  # same declarations.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libinetutil.so.1 "$out/lib/"
    ln -s libinetutil.so.1 "$out/lib/libinetutil.so"

    mkdir -p "$dev/include"
    cp ../common/libinetutil.h ../common/libinetutil_impl.h "$dev/include/"

    runHook postInstall
  '';
}
