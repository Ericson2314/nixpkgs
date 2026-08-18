{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libadm.so.1 -- the old System V "administration" library. Two unrelated
# things live in it, and ZFS wants only the second:
#
#  o	the `ck*`/`get*` prompting helpers and the device/device-group tables
#	(/etc/device.tab), which the SVR4 packaging tools were written against;
#
#  o	`read_vtoc`/`write_vtoc` (rdwr_vtoc.c), the SMI VTOC label reader.
#
# `libzutil` and `libdiskmgt` both link `-ladm` for the second: deciding
# whether a disk is free for a pool means reading its label, and `zpool` has to
# tell an EFI-labelled disk (libefi) from a VTOC-labelled one.
#
# Only libc is needed to link it.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libadm/amd64";
  pname = "libadm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libadm is a /lib library, because the VTOC
    # readers have to work before /usr is mounted.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libadm"

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

  # The headers live in lib/libadm/inc and are installed by the *top*
  # lib/libadm Makefile, which we do not run: the amd64 subdirectory is built
  # directly. ZFS' consumers actually reach `read_vtoc()` through <sys/vtoc.h>,
  # which the headers package already ships, so only the library is
  # load-bearing here -- but shipping the rest costs nothing.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libadm.so.1 "$out/lib/"
    ln -s libadm.so.1 "$out/lib/libadm.so"

    mkdir -p "$dev/include"
    cp ../inc/*.h "$dev/include/"

    runHook postInstall
  '';
}
