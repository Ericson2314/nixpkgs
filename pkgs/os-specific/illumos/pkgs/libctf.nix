{
  lib,
  mkDerivation,

  libcompat,
  compatIsNeeded,
  compatMakeFlags,
  libavl,
  libdwarf,
  libelf,
  sharedLink,
  zlib,
}:

# libctf, the CTF container library that ctfconvert(1) and ctfmerge(1) link
# against, and that libproc/svcs/librestart/libproject/svc-startd/getent link
# against on illumos.
#
# ONE definition, two instances -- see libdwarf.nix, which this follows
# exactly. `illumos.libctf` is the illumos-hosted shared object;
# `buildPackages.illumos.libctf` is the same sources built to run on the
# machine doing the build, which is what the CTF tools use. The scope splices,
# so that is all it takes.
#
# This file used to be a `forIllumos ? ... : ...` conditional selecting between
# `usr/src/lib/libctf/amd64` and `usr/src/tools/ctf/libctf/i386`. The latter
# holds no sources -- it compiles `$(SRC)/lib/libctf/common` under
# `Makefile.ctf.native` -- so keeping it meant two expressions of one library,
# and it is what put the build-host libctf in the onbld `lib/$(MACH)` layout
# that ctfconvert.nix and ctfstabs.nix then had to point at by hand.
let
  link = sharedLink {
    libs = [
      libelf
      libdwarf
      libavl
      zlib
    ];
  };
in
mkDerivation {
  pname = "libctf";

  illumosLib = true;
  libcMinimal = true;

  # Entered directly rather than through ../Makefile's `SUBDIRS = $(MACH)`
  # recursion, which does not forward the macros set here to the sub-make.
  path = "usr/src/lib/libctf/amd64";
  extraPaths = [
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libctf"
    "usr/src/lib/libdwarf/common"
    "usr/src/lib/mergeq"
    "usr/src/common/ctf"
    "usr/src/common/list"
    "usr/src/common/avl"
    "usr/src/common/mapfiles"

    # Reached by the `-idirafter` below on a foreign host; see libdwarf.nix.
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  outputs = [
    "out"
    "dev"
  ];

  buildInputs = link.buildInputs;

  env.NIX_CFLAGS_COMPILE = builtins.toString (link.cflags ++ [ "-Wno-error" ]);

  # libctf dlopen()s its decompressor by absolute path -- `/usr/lib/64/libz.so.1`
  # on illumos, which does not exist on a foreign host. See the CTF_ZLIB_PATH
  # hunk in lib/libctf/common/ctf_lib.c.
  makeFlags = compatMakeFlags {
    hostElf = true;
    extra = [ ''-DCTF_ZLIB_PATH=\"${zlib}/lib/libz.so.1\"'' ];
  };

  buildFlags = [ "all" ];

  # ASSERT() in the CTF sources calls assfail()/assfail3(), and utils.c calls
  # getexecname(); all three are illumos libc and a foreign libc has none of
  # them. `EXTPICS` is the makefile's own hook for extra objects to link into
  # the shared object, which is where they belong: libctf exports them, and
  # ctfconvert and ctfmerge pick them up from it just as they did from the old
  # tools/ctf native build.
  preBuild =
    link.preBuild
    + lib.optionalString compatIsNeeded ''
      $CC -c -fPIC -o compat_ctf_support.o "${libcompat.supportSource}"
      makeFlagsArray+=("EXTPICS=compat_ctf_support.o")
    '';

  # <libctf.h> is installed into /usr/include by the *top* lib/libctf
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  # <ctf_api.h> goes with it, since libctf.h includes it.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libctf.so.1 "$out/lib/"
    ln -s libctf.so.1 "$out/lib/libctf.so"

    mkdir -p "$dev/include"
    cp ../common/libctf.h "$dev/include/"
    mkdir -p "$dev/include/sys"
    cp "$SRC/uts/common/sys/ctf_api.h" "$dev/include/sys/"
    cp "$SRC/uts/common/sys/ctf.h" "$dev/include/sys/"

    runHook postInstall
  '';

  meta.platforms = lib.platforms.unix;
}
