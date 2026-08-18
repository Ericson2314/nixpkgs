{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# <security/cryptoki.h> and the RSA-sourced <security/pkcs11*.h> it includes.
#
# These are the PKCS#11 declarations, and they are installed by the *top*
# lib/pkcs11 Makefile (`ROOTHDRDIR = $(ROOT)/usr/include/security`) rather than
# by any one library underneath it -- which is why they are their own package
# and not part of `libpkcs11`: `libcryptoutil` includes <security/cryptoki.h>
# from its own public header and does not link libpkcs11 at all, so the two
# cannot be one derivation without a cycle.
#
# Headers only. Building the top Makefile's `all` would recurse into
# pkcs11_softtoken, libsoftcrypto and pkcs11_tpm, none of which anything here
# needs.
mkDerivation {
  name = "pkcs11-headers";
  path = "usr/src/lib/pkcs11";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.msg.targ"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
  ];

  headersOnly = true;

  # install(1) will not create the destination directory itself; `ROOTHDRDIR`
  # adds a `security/` component below it, which `mkdir -p` here covers because
  # Makefile.targ's `$(ROOTHDRS)` rule runs $(INS.file) into a directory that
  # already exists.
  installPhase = ''
    mkdir -p "$out/include/security"
    includesPhase
  '';
}
