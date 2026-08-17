{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnvpair,
  libuutil,
}:

# libcontract.so.1 -- the userland side of illumos contracts, out of
# usr/src/lib/libcontract. Contracts are the kernel facility SMF is built on:
# a process contract groups a service's processes so that svc.startd learns
# about their fate as events on a contract file descriptor rather than by
# reaping children, which is what lets a restarter supervise a daemon it did
# not personally fork.
#
# It is packaged because the real `/sbin/init` links
# `-lpam -lbsm -lcontract -lscf`. With libpam packaged alongside this, and
# libbsm and libscf already in the tree, that is the last of init's four
# libraries -- init becomes linkable, which is what replaces the bring-up
# harness with a userland that can run svc.startd.
#
# Unlike libpam, libcontract needs no proto-area header staging: it includes
# its own <libcontract.h> and <libcontract_priv.h>, but they live in common/
# and the Makefile already points -I at SRCDIR.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libcontract/amd64";
  pname = "libcontract";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libcontract"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnvpair
    # Headers only: process_dump.c includes <libuutil.h>, but LDLIBS is just
    # `-lnvpair -lc`.
    libuutil
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for the BUILD.SO override and the `-L`/`-R` rule.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnvpair}/lib -R${libnvpair}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libcontract.so.1 "$out/lib/"
    ln -s libcontract.so.1 "$out/lib/libcontract.so"

    # <libcontract.h> is the public header; <libcontract_priv.h> goes with it
    # because svc.startd and init are both "private" consumers in illumos'
    # sense and include it directly.
    mkdir -p "$dev/include"
    cp ../common/libcontract.h ../common/libcontract_priv.h "$dev/include/"

    runHook postInstall
  '';
}
