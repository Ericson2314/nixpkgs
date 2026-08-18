{
  lib,
  mkDerivation,

  cw,
  libdwarf,
  libctf,
}:

# ctfstabs(1ONBLD): read an `offsets.in` file plus the CTF of a compiled stub,
# and emit the C header of struct offsets that assembly sources include. The
# `-s` half of $(OFFSETS_CREATE) in usr/src/Makefile.master.
#
# Built for ITS OWN host platform, with plain `stdenv`/`$CC`. The scope
# splices, so `buildPackages.illumos.ctfstabs` is already an instance whose
# stdenv targets the build machine; consumers put `ctfstabs` in
# `nativeBuildInputs` and get it. There is nothing here to arrange, and the
# `noCC` + `depsBuildBuild` + `NIX_LDFLAGS_FOR_BUILD` triple that used to be
# here was hand-rolling exactly that.
#
# `usr/src/tools` rather than `usr/src/cmd` is the documented exemption in
# ../default.nix: there is no `cmd/ctfstabs`, this is the only copy.
mkDerivation {
  pname = "ctfstabs";

  # Entered directly rather than through ../Makefile's `SUBDIRS = $(MACH)`
  # recursion, which does not forward $ROOTONBLD to the sub-make. Despite the
  # directory name the build is 64-bit; see tools/ctf/Makefile.ctf.native.
  path = "usr/src/tools/ctf/stabs/i386";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/tools/ctf"

    "usr/src/lib/libctf/common"
    "usr/src/lib/libdwarf/common"
    "usr/src/common/ctf"
    "usr/src/common/list"
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

  # libctf and libdwarf now install into a plain `lib/`, like any other
  # library, so cc-wrapper picks them up from `buildInputs` and there is
  # nothing to point at by hand.
  buildInputs = [
    libctf
    libdwarf
  ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/bin/i386
  '';

  # The onbld layout puts the tool under bin/$(MACH); everything that calls it
  # expects a plain `ctfstabs` on $PATH.
  postFixup = ''
    ln -s i386/ctfstabs $out/bin/ctfstabs
  '';

  meta.platforms = lib.platforms.unix;
}
