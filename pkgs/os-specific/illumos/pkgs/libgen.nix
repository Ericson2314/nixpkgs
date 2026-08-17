{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libgen.so.1 -- the "generic" SVR4 utility library: `mkdirp`/`rmdirp`,
# `pathfind`, `gmatch`, `bgets`/`bufsplit`, `copylist`, `p2open`, the
# `strccpy`/`strecpy`/`strfind`/`strtrns` string helpers, and the old
# `compile`/`step` regular-expression interface out of <regexpr.h>.
#
# It is here because libscf links `-lgen`: `midlevel.c` and `scf_type.c` use
# it. libdevinfo and a good deal of the rest of userland want it too.
#
# Sixteen objects, one mapfile, and `-lc` as its only dependency, so this is
# the simplest possible `illumosLib` package.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libgen/amd64";
  pname = "libgen";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libgen"

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

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  # <regexpr.h> is installed into /usr/include by the *top* lib/libgen
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  # Ship it (and the private headers it and libscf's users reach for) out of
  # the source directory. <libgen.h> itself lives in usr/src/head and so is
  # already part of `headers`.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libgen.so.1 "$out/lib/"
    ln -s libgen.so.1 "$out/lib/libgen.so"

    mkdir -p "$dev/include"
    cp ../inc/regexpr.h "$dev/include/"

    runHook postInstall
  '';
}
