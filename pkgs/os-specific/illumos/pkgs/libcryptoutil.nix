{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  # <cryptoutil.h> -- this library's own public header -- opens with
  # `#include <security/cryptoki.h>`, so anything that includes it needs the
  # PKCS#11 headers on its path as well. See pkcs11-headers.nix for why those
  # are a package of their own.
  pkcs11-headers,
}:

# libcryptoutil.so.1 -- the private helper library shared by the Cryptographic
# Framework's userland pieces: parsing /etc/crypto/pkcs11.conf and
# /etc/crypto/kcf.conf, the PKCS#11 mechanism-name<->number tables, hex/PIN
# handling, and `pkcs11_get_random()`.
#
# ZFS reaches it twice over: `libpkcs11` links `-lcryptoutil` outright, and so
# does `libfakekernel`, whose `random_get_bytes()` is implemented on top of
# `pkcs11_get_urandom()`.
#
# Only libc is needed to link it.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libcryptoutil/amd64";
  pname = "libcryptoutil";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: a /lib library, since the framework has to
    # come up before /usr is mounted.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libcryptoutil"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    pkcs11-headers
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

  # <cryptoutil.h> is the top lib/libcryptoutil Makefile's single `HDRS` entry,
  # and that Makefile is the recursive driver we do not run: the amd64
  # subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libcryptoutil.so.1 "$out/lib/"
    ln -s libcryptoutil.so.1 "$out/lib/libcryptoutil.so"

    mkdir -p "$dev/include"
    cp ../common/cryptoutil.h "$dev/include/"

    runHook postInstall
  '';
}
