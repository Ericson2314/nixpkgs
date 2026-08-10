{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# librename.so.1 -- `renameat_atomic`: create a file under a temporary name in
# the target directory and `renameat` it into place, so a reader never sees a
# partially written file. One object, libc only.
#
# Packaged as part of the `dladm`/`ipadm` closure: the persistent datalink and
# address configuration in /etc/dladm is rewritten this way rather than
# truncated in place.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/librename/amd64";
  pname = "librename";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/librename"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  # <librename.h> is installed by the *top* lib/librename Makefile (its
  # `HDRS`), which we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp librename.so.1 "$out/lib/"
    ln -s librename.so.1 "$out/lib/librename.so"

    mkdir -p "$dev/include"
    cp ../common/librename.h "$dev/include/"

    runHook postInstall
  '';
}
