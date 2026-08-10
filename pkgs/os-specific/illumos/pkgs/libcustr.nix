{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libcustr.so.1 -- "custr", a growable C string: `custr_alloc`, `custr_append`,
# `custr_appendc`, `custr_cstr`. One object, no dependencies beyond libc.
#
# On the path to `dladm`: libdladm and the datalink commands build up device
# and property names with custr rather than open-coded realloc loops.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libcustr/amd64";
  pname = "libcustr";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: custr is used by /sbin utilities on some
    # distributions, so the library lands in /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libcustr"

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

  # <libcustr.h> is installed by the *top* lib/libcustr Makefile (its `HDRS`),
  # which we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libcustr.so.1 "$out/lib/"
    ln -s libcustr.so.1 "$out/lib/libcustr.so"

    mkdir -p "$dev/include"
    cp ../common/libcustr.h "$dev/include/"

    runHook postInstall
  '';
}
