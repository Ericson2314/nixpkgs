{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libumem,
}:

# libidspace.so.1 -- the kernel's id_space allocator, built for userland: a
# vmem arena restricted to integers, handing out and recycling small unique
# IDs (`id_alloc`, `id_free`) without ever reusing one that is still live.
# `common/idspace/id_space.c` is the code shared with the kernel; the library
# provides the userland vmem underneath it, which is why it links `-lumem`
# rather than plain `-lc`.
#
# Packaged for the `dladm`/`ipadm` closure, where it backs the allocation of
# datalink and IP-interface identifiers.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libidspace/amd64";
  pname = "libidspace";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/libidspace"

    # id_space.o is compiled out of the code shared with the kernel, via
    # Makefile.com's own `pics/%.o: $(COMDIR)/%.c` rule.
    "usr/src/common/idspace"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libumem
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. libumem gets a `-R` as well as its `-L`:
  # without it there is no DT_RUNPATH, hence no nix reference, and the
  # dependency silently drops out of the closure. libumem itself needs only
  # libc, so there is no further transitive path to add.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libumem}/lib -R${libumem}/lib \$(LDLIBS)")
  '';

  # <libidspace.h> is installed by the *top* lib/libidspace Makefile (its
  # `HDRS`), which we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libidspace.so.1 "$out/lib/"
    ln -s libidspace.so.1 "$out/lib/libidspace.so"

    mkdir -p "$dev/include"
    cp ../common/libidspace.h "$dev/include/"

    runHook postInstall
  '';
}
