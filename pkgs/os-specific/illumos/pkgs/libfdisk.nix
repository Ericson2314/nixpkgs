{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libfdisk.so.1 -- reading and writing the x86 master boot record's partition
# table (`libfdisk_init`, `fdisk_get_solaris_part`, the extended-partition
# walker). Only libc is needed to link it.
#
# Packaged because `libdiskmgt` links it on x86 -- `i386_LDLIBS = -lfdisk` in
# its Makefile.com -- and `zpool` links libdiskmgt to decide whether a disk it
# has been handed is already in use.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libfdisk/amd64";
  pname = "libfdisk";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: fdisk(8) lives in /usr/sbin but the label
    # readers are wanted from the miniroot, so the library goes to /lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libfdisk"

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

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libfdisk.so.1 "$out/lib/"
    ln -s libfdisk.so.1 "$out/lib/libfdisk.so"

    mkdir -p "$dev/include"
    cp ../common/libfdisk.h "$dev/include/"

    runHook postInstall
  '';
}
