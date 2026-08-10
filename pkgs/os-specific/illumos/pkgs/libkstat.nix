{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libkstat.so.1 -- the userland side of the kernel statistics framework. It is
# a thin wrapper over /dev/kstat: `kstat_open` mmaps the chain, `kstat_read`
# copies one out, and `kstat_lookup` walks it by module/instance/name.
#
# Wanted here for `dladm show-link -s` and friends: every MAC driver publishes
# its packet and error counters as kstats, so the datalink commands read them
# rather than adding an ioctl of their own.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libkstat/amd64";
  pname = "libkstat";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libkstat is a root-filesystem library, i.e.
    # /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libkstat"

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

  # <kstat.h> is installed by the *top* lib/libkstat Makefile, which we do not
  # run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libkstat.so.1 "$out/lib/"
    ln -s libkstat.so.1 "$out/lib/libkstat.so"

    mkdir -p "$dev/include"
    cp ../kstat.h "$dev/include/"

    runHook postInstall
  '';
}
