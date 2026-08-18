{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
}:

# usr/src/tools/libcompat, built by its own makefile rather than reproduced
# here. It is what makes gate source compile against a foreign libc: a gathered
# set of "ELF-y" illumos headers, the shims for the pieces a foreign libc has
# no counterpart for, and `libcompat.a` holding the entry points it is missing
# outright (assfail(), panic(), getexecname(), strtonum(), link_ver_string).
#
# Three outputs, and the split matters:
#
#   include/         the headers gathered out of usr/src/uts
#   include-native/  the checked-in shims
#   lib/$(MACH)/     libcompat.a
#
# include-native/sys/elf.h deliberately shadows include/sys/elf.h: the former
# forwards to the *host's* <elf.h>, for a consumer that links the host libelf,
# and the latter is illumos' real one. A consumer picks a side by which
# directory it -I's first, so the two cannot be merged.
#
# Build platform only. Nothing illumos-hosted wants any of this -- an illumos
# host's libc *is* illumos' -- and giving it a target instance would make it a
# cross build that needs a libc it is itself a prerequisite for.
mkDerivation {
  pname = "libcompat";
  path = "usr/src/tools/libcompat";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"

    # The Makefile gathers its header list out of these two.
    "usr/src/uts/common/sys"
    "usr/src/uts/intel/sys"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install

    # Makefile.master:814 sets NATIVECC to $(NATIVE_CW) --tag native, so the
    # compile goes through cw(1), which is what translates the Studio spellings
    # (-_gcc=, -errtags=, -xc99=) that NATIVE_CFLAGS is written in. Handing raw
    # gcc those flags fails outright. cw itself builds with plain gcc, so this
    # is not a cycle.
    cw
  ];

  # The Makefile indexes two things by $(MACH): the per-ISA header directory
  # under usr/src/uts (i386 -> intel) and $(ROOTONBLDLIBMACH), where the archive
  # installs. A build-host tool gets no MACH unless it asks, so ask.
  illumosOnbldMach = true;

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
  ];

  meta = {
    description = "illumos headers and shims for building gate source against a foreign libc";
    platforms = lib.platforms.unix;
    license = lib.licenses.cddl;
  };
}
