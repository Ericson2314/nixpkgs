{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libumem,
  libcryptoutil,
  libsocket,
  libavl,
  pkcs11-headers,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's own dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libfakekernel.so.1 -- enough of the kernel's own API, implemented on top of
# libc, that kernel source can be compiled and run in a process: `mutex_enter`,
# `kmem_alloc`, `taskq_dispatch`, `cv_wait`, `cmn_err`, `ddi_copyin`, the
# cyclic and callout machinery, `random_get_bytes` (which is why it links
# libcryptoutil), and the bit helpers in `kmisc.c`.
#
# It is the substrate libzpool is built on -- that is the whole of
# uts/common/fs/zfs compiled for userland, which zdb(8) and ztest run the DMU
# out of.
#
# Here it is wanted for something much smaller: `zpool` uses `highbit64()` and
# `lowbit64()` (the `HISTO()` macro in <sys/fs/zfs.h>, for the `zpool iostat
# -w` latency histograms), and those are kernel functions with no libc
# counterpart. Upstream gets them by linking `-lzpool`, which in turn links
# this; we cannot build libzpool yet (its Makefile needs `dtrace -h`), so zpool
# links this directly. Nothing else in it is used, and nothing in it starts a
# thread or takes a lock unless called.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libfakekernel/amd64";
  pname = "libfakekernel";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it, with the reason in a comment: libzpool wants
    # it in the root filesystem.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libfakekernel"

    # `INCS += -I$(SRC)/uts/common -I$(SRC)/common`: this library is compiled
    # against the *kernel's* headers, not the userland ones, which is the
    # entire point of it. `sid.c` is also copied out of uts/common/os by a rule
    # in Makefile.com.
    "usr/src/uts/common"
    "usr/src/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libumem
    libcryptoutil
    libsocket
    libavl
    pkcs11-headers
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # Note that Makefile.com *assigns* `CPPFLAGS = $(CPPFLAGS.first)` rather than
  # appending, with a comment saying so: its own `-I../common` and the kernel
  # include paths have to come before anything the environment supplies. That
  # is why the installed headers are passed through CPPFLAGS.first here as
  # everywhere else, and why nothing may be added to CPPFLAGS itself.
  #
  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I../common -I${headers}/include -I${libumem.dev}/include -I${libcryptoutil.dev}/include -I${pkcs11-headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libumem}/lib -R${libumem}/lib -L${libcryptoutil}/lib -R${libcryptoutil}/lib -L${libsocket}/lib -R${libsocket}/lib -L${libavl}/lib -R${libavl}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # libfakekernel installs no headers of its own -- its consumers include the
  # kernel's, out of the source tree. `sys/` here is the small shim set
  # (<sys/kmem.h> substitutes and friends) that lib/libfakekernel/common/sys
  # carries, which libzpool would need.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libfakekernel.so.1 "$out/lib/"
    ln -s libfakekernel.so.1 "$out/lib/libfakekernel.so"

    mkdir -p "$dev/include"
    cp -r ../common/sys "$dev/include/"

    runHook postInstall
  '';
}
