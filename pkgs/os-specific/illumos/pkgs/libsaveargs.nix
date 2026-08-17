{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libdisasm,
}:

# libsaveargs.so.1 -- decodes an amd64 function prologue to recover the
# argument registers a function was called with. That is what makes `pstack`
# and mdb able to print arguments on amd64, where the ABI passes them in
# registers and nothing on the stack records them; the kernel and userland are
# compiled with `-msave-args` so the prologue spills them, and this library
# reads that prologue back.
#
# Here only as a dependency: `libproc`s *amd64* Makefile adds `-lsaveargs`
# (Makefile.com does not mention it), and the chain runs on to `svc.startd`.
#
# Same two-flavour build as libdisasm -- see the note on `all.library.targ`
# below -- and it links `-ldisasm` to decode the instructions.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libsaveargs/amd64";
  pname = "libsaveargs";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsaveargs"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libdisasm
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
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libdisasm}/lib -R${libdisasm}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libsaveargs.so.1 "$out/lib/"
    ln -s libsaveargs.so.1 "$out/lib/libsaveargs.so"

    mkdir -p "$dev/include"
    cp ../common/saveargs.h "$dev/include/"

    runHook postInstall
  '';
}
