{
  lib,
  stdenv,
  mkDerivation,

  cw,
  libdwarf,

  buildPackages,
}:

# libctf, the CTF container library that ctfconvert(1) and ctfmerge(1) link
# against.
#
# One attribute, two source trees, chosen by the platform being built for --
# the same arrangement as ld.nix, explained at length there. The platform comes
# from the package set, not from the name: `buildPackages.illumos.libctf` is
# the build-host build (usr/src/tools/ctf/libctf -- the only one the CTF tools
# can use here), and `illumos.libctf` in a cross set is the illumos-hosted one
# under usr/src/lib/libctf. Do not put the platform back in the attribute name.
#
# Like the rest of tools/ctf the build-host form is a build-host program, so it
# uses `noCC` plus the host compiler via `depsBuildBuild` and never touches the
# illumos cross toolchain.
let
  forIllumos = stdenv.hostPlatform.isSunOS;
in
mkDerivation {
  pname = "libctf";
  noCC = true;

  # Entered directly rather than through ../Makefile's `SUBDIRS = $(MACH)`
  # recursion, which does not forward $ROOTONBLD to the sub-make. Despite the
  # directory name the build is 64-bit; see tools/ctf/Makefile.ctf.native.
  path = if forIllumos then "usr/src/lib/libctf/amd64" else "usr/src/tools/ctf/libctf/i386";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/ctf"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/lib/libctf"
    "usr/src/lib/libdwarf/common"
    "usr/src/lib/mergeq"
    "usr/src/common/ctf"
    "usr/src/common/list"
    "usr/src/common/avl"
    "usr/src/uts/common/sys"
    "usr/src/head"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "MACH=i386"
    "MACH64=amd64"
  ];

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [ cw ];

  # libdwarf installs into lib/$(MACH), which is not the lib/ that cc-wrapper
  # would pick up from a depsBuildBuild entry, so point at it by hand. These
  # are the build-platform spellings of NIX_LDFLAGS, honoured by the
  # $CC_FOR_BUILD wrapper.
  NIX_LDFLAGS_FOR_BUILD = "-L${libdwarf}/lib/i386 -rpath ${libdwarf}/lib/i386";

  # libctf dlopen()s its decompressor by absolute path -- /usr/lib/64/libz.so.1
  # on illumos, which does not exist here. See the CTF_ZLIB_PATH hunk in
  # lib/libctf/common/ctf_lib.c.
  NIX_CFLAGS_COMPILE_FOR_BUILD = ''-DCTF_ZLIB_PATH="${buildPackages.zlib}/lib/libz.so.1"'';

  depsBuildBuild = [
    buildPackages.stdenv.cc
    buildPackages.elfutils
    buildPackages.zlib
  ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/lib/i386
  '';

  meta.platforms = lib.platforms.unix;
}
