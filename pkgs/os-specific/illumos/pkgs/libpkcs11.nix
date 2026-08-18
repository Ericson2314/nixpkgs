{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libcryptoutil,
  pkcs11-headers,
}:

# libpkcs11.so.1 -- the PKCS#11 "meta slot" provider. It is not a token
# implementation: it reads /etc/crypto/pkcs11.conf, dlopen()s the providers
# named there (pkcs11_kernel, pkcs11_softtoken), presents their slots as one
# virtual slot, and routes each `C_*` call to whichever of them can do the
# mechanism.
#
# ZFS wants it because `libzfs` links `-lpkcs11`: `zfs_crypto.c`-adjacent code
# and the send/receive checksum paths ask the framework for SHA-256 rather than
# carrying their own.
#
# Nothing here needs the providers to exist at build time -- they are found by
# name at run time, and an empty pkcs11.conf simply yields a token-less
# library. So the providers (pkcs11_softtoken, pkcs11_kernel, libsoftcrypto)
# are deliberately not packaged with it; add them when something actually needs
# a mechanism.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/pkcs11/libpkcs11/amd64";
  pname = "libpkcs11";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/pkcs11/libpkcs11"
    # `INCDIR = ../../include`: the RSA-sourced <pkcs11.h>/<pkcs11t.h> that the
    # sources include without the `security/` prefix, out of the tree rather
    # than out of `pkcs11-headers`.
    "usr/src/lib/pkcs11/include"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libcryptoutil
    pkcs11-headers
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. Every `-L` gets a matching `-R`: without it
  # there is no DT_RUNPATH and no nix reference, so the dependency is absent
  # from the closure.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libcryptoutil.dev}/include -I${pkcs11-headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libcryptoutil}/lib -R${libcryptoutil}/lib \$(LDLIBS)")
  '';

  # No `dev` output: the public headers are <security/cryptoki.h> and friends,
  # which `pkcs11-headers` ships.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libpkcs11.so.1 "$out/lib/"
    ln -s libpkcs11.so.1 "$out/lib/libpkcs11.so"

    runHook postInstall
  '';
}
