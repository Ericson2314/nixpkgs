{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libdisasm.so.1 -- the instruction disassembler behind `dis(1)` and mdb's
# `::dis`. Here only as a dependency: `libsaveargs` links `-ldisasm` to decode
# an amd64 function prologue, `libproc` links `-lsaveargs`, and the chain runs
# on to `svc.startd`.
#
# lib/libdisasm builds two flavours of itself -- `TYPES = library standalone`,
# the standalone one being the copy linked into kmdb -- driven by a recursive
# make over `CURTYPE`. Only the shared library is wanted here, so `TYPES` is
# overridden on the command line; the standalone rule links with `$(LD)`
# directly and has no reason to work in this arrangement.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdisasm/amd64";
  pname = "libdisasm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdisasm"

    # `ISASRCDIR=../$(MACH)/`: the x86 instruction tables are shared with the
    # kernel disassembler and live outside the library directory.
    "usr/src/common/dis"

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

  # `all` recurses -- `@$(MAKE) all.library.targ CURTYPE=library` -- and the
  # command-line `POST_PROCESS_O=:` that mkDerivation passes does not survive
  # into that sub-make, so Makefile.lib:191 rebuilds it as `; $(CTFCONVERT_POST)`
  # and the recipe line starts with a bare `;`. Build the leaf target directly
  # instead, which also skips the `standalone` flavour we do not want.
  buildFlags = [ "all.library.targ" ];

  makeFlags = [ "CURTYPE=library" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdisasm.so.1 "$out/lib/"
    ln -s libdisasm.so.1 "$out/lib/libdisasm.so"

    mkdir -p "$dev/include"
    cp ../common/libdisasm.h "$dev/include/"

    runHook postInstall
  '';
}
