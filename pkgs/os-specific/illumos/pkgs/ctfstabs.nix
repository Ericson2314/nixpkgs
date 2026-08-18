{
  lib,
  mkDerivation,

  cw,
  libdwarf,
  libctf,
  libcompat,
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

  # Installs into, or reads from, the onbld $(ROOTONBLD)/bin/$(MACH) layout,
  # so it needs MACH set even when it is built for the build host.
  illumosOnbldMach = true;

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"

    # tools/Makefile.tools points these at $(SRC)/tools/libcompat, which is not
    # in this package's filtered source. `libcompat` is that directory, built.
    # The host-elf profile is separate and the CTF tools are the consumers that
    # want it: it sends <sys/elf.h> to the host's <elf.h>, which is right here
    # because these tools link the host libelf.
    "COMPAT_DIR=${libcompat}/include-native"
    "COMPAT_INC=${libcompat}/include"
    "COMPAT_HOSTELF=${libcompat}/include-host-elf"
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
