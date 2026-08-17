{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsecdb,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libtsol.so.2 -- the Trusted Extensions label library: conversions between
# binary sensitivity labels and their text and hex forms (`bltos`, `stobl`,
# `h_alloc`), the `labeld` door client that performs them, and the process and
# file label accessors (`getplabel`, `getlabel`, `setflabel`).
#
# Trusted Extensions is not configured here and never will be for this
# bring-up; the label calls all degrade to the single default label when
# `labeld` is absent. It is packaged because libbsm links `-ltsol`
# unconditionally, and libbsm is what `svc.configd` needs for its `adt_*`
# audit sessions.
#
# Note the SONAME is libtsol.so.2, not .1 -- `VERS = .2` in Makefile.com.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libtsol/amd64";
  pname = "libtsol";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libtsol"

    # blabel.c/ltos.c/stol.c are not under lib/libtsol: `COMMONDIR` points at
    # the shared label code, and there is an explicit pics rule for it.
    "usr/src/common/tsol"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsecdb
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
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libsecdb}/lib -R${libsecdb}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <tsol/label.h> is installed into /usr/include/tsol by the *top* lib/libtsol
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  # It goes under a `tsol/` subdirectory because that is how consumers spell
  # the include -- libbsm's adt code says <tsol/label.h>.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libtsol.so.2 "$out/lib/"
    ln -s libtsol.so.2 "$out/lib/libtsol.so"

    mkdir -p "$dev/include/tsol"
    cp ../common/label.h "$dev/include/tsol/"

    runHook postInstall
  '';
}
