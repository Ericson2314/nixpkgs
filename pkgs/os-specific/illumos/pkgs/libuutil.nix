{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libuutil.so.1 -- the "userland utility" library: the arena/allocation
# wrappers (`uu_zalloc`), the AVL and list containers layered on
# `usr/src/common/avl`, `uu_warn`/`uu_die` program-name error reporting, and
# the string/strtoint helpers. It is the common runtime that svc.startd,
# zfs(1M) and the SMF libraries are written against.
#
# We build it because `libidmap.so.1` links against it, and libidmap is in
# turn `libsec.so.1`'s dependency -- so it has to be findable on the link path
# of anything that links `-lsec`.
#
# `Makefile.shared.com`'s `CPPFLAGS += -I../../common/inc` is dead, exactly as
# in libsocket: resolved from the amd64 build directory it names
# `usr/src/lib/common/inc`, which does not exist in the gate.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libuutil/amd64";
  pname = "libuutil";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libuutil"

    # `avl.o` is compiled out of the code shared with the kernel, via
    # `Makefile.shared.targ`'s `pics/%.o: $(AVLDIR)/%.c` rule.
    "usr/src/common/avl"

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

  # <libuutil.h> is installed into /usr/include by the *top* lib/libuutil
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  # Ship it (and the `libuutil_common.h` it includes) from the source
  # directory, since libidmap includes it.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libuutil.so.1 "$out/lib/"
    ln -s libuutil.so.1 "$out/lib/libuutil.so"

    mkdir -p "$dev/include"
    cp ../common/libuutil.h ../common/libuutil_common.h "$dev/include/"

    runHook postInstall
  '';
}
