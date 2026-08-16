{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libumem.so.1 -- the slab allocator as a userland malloc, plus the debugging
# facilities (`UMEM_DEBUG`, `UMEM_LOGGING`, the `::umem_verify` side that mdb
# reads). `svccfg` links it, as does most of the SMF stack.
#
# Only the shared library is built here, not the standalone flavour.
# `lib/libumem` builds twice -- `TYPES = library standalone` in the amd64
# Makefile -- and the standalone is a `-r` relocatable object linked with
# `$(BREDUCE)` for kmdb to embed, checked against `linktest_stand.o` to prove
# it has no external dependencies. kmdb is not packaged, so the whole flavour
# is dropped by building the library flavour's leaf target directly; see
# `buildFlags`.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libumem/amd64";
  pname = "libumem";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libumem"

    # `asm_subr.S` and `umem_genasm.c` come from $(ISASRCDIR) = ../i386.
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

  # Not `all`: `Makefile.targ`'s `all` is `all.library all.standalone`, each of
  # which re-enters make (`@$(MAKE) $@.targ CURTYPE=...`), and dmake does not
  # carry this package's command-line macros into that sub-make -- `POST_PROCESS_O=:`
  # is lost, `Makefile.lib`'s `POST_PROCESS_O += ; $(CTFCONVERT_POST)` takes
  # effect again, and the recipe comes out starting with a bare `;`:
  #
  #     ; ctfconvert -L VERSION pics/init_lib.o
  #     sh: syntax error: unexpected ";"
  #
  # Naming the leaf target and setting `CURTYPE` here skips the recursion
  # altogether, and drops the standalone flavour with it.
  buildFlags = [
    "all.library.targ"
    "CURTYPE=library"
  ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  # <umem.h> and <umem_impl.h> are installed into /usr/include by the top
  # lib/libumem Makefile, which we do not run.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libumem.so.1 "$out/lib/"
    ln -s libumem.so.1 "$out/lib/libumem.so"

    mkdir -p "$dev/include"
    cp ../common/umem.h ../common/umem_impl.h "$dev/include/"

    runHook postInstall
  '';
}
