{
  lib,
  mkDerivation,

  cw,
  compat,
}:

# elfextract(1ONBLD): dumps a linked ELF object as assembler `.byte` output,
# used to embed the 64-bit `dboot` stub into `unix`
# (uts/i86pc/unix/Makefile:181).
#
# A build-host program. Nothing here says so: `buildPackages.illumos.elfextract`
# is this package built for the build platform, and mkDerivation applies the
# native-build overlay off the platforms. It
# needs no libelf -- it mmaps the file and walks
# Elf64_Ehdr by hand -- but it does need illumos' <sys/elf.h>, which comes from
# the staged header set in pkgs/compat.
mkDerivation {
  pname = "elfextract";

  path = "usr/src/tools/elfextract";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
  ];

  # Installs into, or reads from, the onbld $(ROOTONBLD)/bin/$(MACH) layout,
  # so it needs MACH set even when it is built for the build host.
  illumosOnbldMach = true;

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"

    # LDCHECKS and STRIP_STABS used to be restated here. Both now come from
    # mkDerivation's build-host overlay, along with the rest of the Solaris
    # link-editor options GNU ld rejects.

    # Makefile.master:150 spells the installer `install`, which on a Linux
    # build host is coreutils' and does not take -f. illumos' own is
    # install.bin; tools/ctf/Makefile.ctf.native redirects it the same way.
    "INS=install.bin"
  ];

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [ cw ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/bin/i386
    export NIX_CFLAGS_COMPILE="$NIX_CFLAGS_COMPILE ${compat.stagedCflags}"
  '';

  # The onbld layout puts the tool under bin/$(MACH), which is how
  # Makefile.master:124 spells it; everything here reaches it by plain name on
  # $PATH instead.
  postFixup = ''
    ln -s i386/elfextract $out/bin/elfextract
  '';

  meta.platforms = lib.platforms.unix;
}
