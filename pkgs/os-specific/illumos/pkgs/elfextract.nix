{
  lib,
  mkDerivation,

  cw,
  compat,
  buildPackages,
}:

# elfextract(1ONBLD): dumps a linked ELF object as assembler `.byte` output,
# used to embed the 64-bit `dboot` stub into `unix`
# (uts/i86pc/unix/Makefile:181).
#
# A build-host program, so `noCC` plus the host compiler via `depsBuildBuild`;
# see pkgs/libdwarf.nix. It needs no libelf -- it mmaps the file and walks
# Elf64_Ehdr by hand -- but it does need illumos' <sys/elf.h>, which comes from
# the staged header set in pkgs/compat.
mkDerivation {
  pname = "elfextract";
  noCC = true;

  path = "usr/src/tools/elfextract";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
  ];

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "MACH=i386"
    "MACH64=amd64"

    # NATIVE_MACH is $(MACH:amd64=i386) (Makefile.master:736), so NATIVE_CFLAGS
    # would carry -m32 and the build host would need a 32-bit glibc. This is an
    # ordinary 64-bit host program; tools/ctf/Makefile.ctf.native does the same
    # for the CTF tools.
    "NATIVE_MACH=amd64"

    # LDCHECKS is -zassert-deflib -zguidance -zfatal-warnings, all Solaris
    # link-editor options (Makefile.master:720). This is linked by GNU ld on
    # the build host, which rejects them outright.
    "LDCHECKS="

    # POST_PROCESS ends in $(STRIP_STABS), i.e. `$(STRIP) -x $@`
    # (Makefile.master:979). STRIP is undefined for a `noCC` derivation, so the
    # recipe degenerates to running `-x` as a command. These are build tools,
    # not deliverables, and nothing needs them stripped; tools/sgs/Makefile.com
    # neutralises the same macro.
    "STRIP_STABS=:"

    # Makefile.master:150 spells the installer `install`, which on a Linux
    # build host is coreutils' and does not take -f. illumos' own is
    # install.bin; tools/ctf/Makefile.ctf.native redirects it the same way.
    "INS=install.bin"
  ];

  buildFlags = [ "install" ];
  dontInstall = true;

  extraNativeBuildInputs = [ cw ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  # The build installs as it goes, so the target directory has to exist before
  # it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/bin/i386
    export NIX_CFLAGS_COMPILE_FOR_BUILD="$NIX_CFLAGS_COMPILE_FOR_BUILD ${compat.stagedCflags}"
  '';

  # The onbld layout puts the tool under bin/$(MACH), which is how
  # Makefile.master:124 spells it; everything here reaches it by plain name on
  # $PATH instead.
  postFixup = ''
    ln -s i386/elfextract $out/bin/elfextract
  '';

  meta.platforms = lib.platforms.unix;
}
