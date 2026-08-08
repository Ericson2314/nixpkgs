{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,

  crt,
  headers,
  libcMinimal,
}:

# libdl.so.1. There is no `usr/src/lib/libdl` -- on illumos libdl is a *filter*
# on the runtime linker, and it is built out of the link-editor tree at
# `usr/src/cmd/sgs/libdl`. The `dlopen`/`dlsym`/`dladdr` implementations live in
# `ld.so.1` and are re-exported by `libc.so.1`, so this library, like
# libpthread, contains no code at all: `cmd/sgs/libdl/amd64/Makefile` says
#
#     DYNFLAGS +=	-F /usr/lib/$(MACH64)/ld.so.1
#
# and the entire content is `common/mapfile-vers`. It exists so that an
# unconditional `-ldl` -- which essentially every autoconf project passes on a
# "SVR4-ish" system -- resolves.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/libdl/amd64";
  pname = "libdl-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/Makefile.filter.com"
    "usr/src/lib/Makefile.filter.targ"
    "usr/src/cmd/sgs/libdl"

    "usr/src/common/mapfiles"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld-native
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
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

  # `illumosSetupHook`'s `fixIllumosInstallDirs` rewrites every `/usr/lib` in
  # every Makefile to `$(LIBDIR)`, which is right for install paths but wrong
  # here: the filtee in `DYNFLAGS += -F /usr/lib/$(MACH64)/ld.so.1` is a
  # *runtime* path, and rewriting it bakes libdl's own `$out/lib/amd64/ld.so.1`
  # -- a file that does not exist -- into `DT_FILTER`. Point it back at the
  # runtime linker's own `DT_SONAME` instead (rtld.nix installs `ld.so.1` with
  # soname `/lib/amd64/ld.so.1`), so the filtee resolves to the already-mapped
  # interpreter rather than triggering a load.
  preBuild = ''
    sed -i -E 's|-F[[:space:]]+[^[:space:]]*ld\.so\.1|-F /lib/$(MACH64)/ld.so.1|' Makefile
    grep -n 'ld\.so\.1' Makefile
  '';

  # Deliberately no `BUILD.SO` override -- see the long comment in
  # libpthread.nix. `lib/Makefile.filter.targ:31` already defines a filter
  # specific `BUILD.SO` that calls `$(LD)` directly *and* passes
  # `$(MAPFILECLASS)` (`-64`). Overriding it and dropping `-64` makes ld emit a
  # silently 32-bit object, since a filter has no input objects to infer the
  # ELF class from.

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld-native}/bin/ld "$@"
      ''
    }"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdl.so.1 "$out/lib/"
    ln -s libdl.so.1 "$out/lib/libdl.so"

    runHook postInstall
  '';
}
