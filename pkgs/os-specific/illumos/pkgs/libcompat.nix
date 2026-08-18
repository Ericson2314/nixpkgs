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
# THE ONLY PACKAGE FOR ANY OF THIS. There used to be a second one, `compat`,
# which reproduced the header gather by hand in its own `buildCommand` while
# this one ran the makefile. Two spellings of one thing at two store paths is
# how the wrong one comes to be fixed later, so the consumers of that one --
# the CTF tools, libctf, libdwarf, elfextract, vtfontcvt, mbh_patch, sgsmsg,
# mkfs-ufs -- name this one now, through the `passthru` profiles below.
#
# The directories, and the split between them matters:
#
#   include/           the headers gathered out of usr/src/uts and usr/src/head
#   include-sys/       include/sys alone; see postInstall
#   include-native/    the checked-in shims
#   include-host-elf/  <sys/elf.h> forwarded to the host's <elf.h>
#   include-overlay/   the headers that sit in FRONT of the gate's own
#   src/libcompat/     the shim halves a consumer compiles itself
#   lib/$(MACH)/       libcompat.a
#
# include-native/sys/elf.h deliberately shadows include/sys/elf.h: the former
# forwards to the *host's* <elf.h>, for a consumer that links the host libelf,
# and the latter is illumos' real one. A consumer picks a side by which
# directory it -I's first, so the two cannot be merged.
#
# Build platform only. Nothing illumos-hosted wants any of this -- an illumos
# host's libc *is* illumos' -- and giving it a target instance would make it a
# cross build that needs a libc it is itself a prerequisite for.
mkDerivation (finalAttrs: {
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
    "usr/src/head"
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

  # Three things the gate's `install` target does not hand over, patched in
  # here rather than reproduced wholesale. Each is a small gap and each belongs
  # upstream in `usr/src/tools/libcompat`; the commit message spells out the
  # change. Until then this is the ONE place they live, which is the point of
  # the merge -- the alternative, and what was here before, was a second
  # package re-gathering the whole header set in order to add them.
  postInstall = ''
    mkdir -p "$out/include-native/sys"

    # <sys/inttypes.h> and <sys/stdint.h> are illumos' spellings of the ISO
    # headers. The real ones reach <sys/int_types.h>, which redefines the whole
    # intN_t family and collides with the host's <stdint.h>, so forward to the
    # host's instead. elfextract.c includes the first; <sys/multiboot2.h>,
    # which mbh_patch walks, includes the second.
    for h in inttypes stdint; do
      printf '#include <%s.h>\n' "$h" > "$out/include-native/sys/$h.h"
    done

    # native_support.c is compiled into libcompat.a by the makefile, and that
    # archive is not position-independent, so libctf -- a shared object -- has
    # to compile the source itself with -fPIC. install_compat_src installs the
    # other three files of common/ as source for a related reason; this one is
    # simply missing from its list.
    cp common/native_support.c "$out/src/libcompat/native_support.c"

    # A fourth profile, and the one the gate's `install_hdrs` does not express.
    #
    # `include/` gathers two lists that are not interchangeable: SYSHDRS, the
    # illumos type vocabulary out of uts/common/sys, and HEADHDRS, the ELF API
    # out of head -- <elf.h>, <libelf.h>, <gelf.h> and friends. sgs wants both,
    # and that is what `stagedCflags` gives it.
    #
    # The CTF tools want the first WITHOUT the second. They link elfutils, so
    # illumos' <libelf.h> and <gelf.h> ahead of the host's are the same structs
    # declared twice: `Elf64_Shdr` becomes something that is not a struct and
    # ctf_dwarf.c stops compiling. `include-host-elf` settles <sys/elf.h> the
    # same way but cannot settle these -- an `#include_next` from there lands
    # in `include/` and finds illumos' again.
    #
    # No new list is written down for this: the split is already structural,
    # HEADHDRS being exactly the top level of `include/` and SYSHDRS its `sys`
    # subdirectory, so the profile is one symlink rather than a second gather.
    # Upstream should install the two halves separately instead.
    mkdir -p "$out/include-sys"
    ln -s ../include/sys "$out/include-sys/sys"
  '';

  # The compile and link profiles a consumer names, rather than each
  # re-deriving the -I/-include incantation. See the makefile's comment on why
  # the include directories must stay apart: a consumer picks a profile by
  # which one it searches first.
  passthru =
    let
      self = finalAttrs.finalPackage;
    in
    {
      # "staged": the host libc wins, illumos' headers layered on top, with the
      # shims of `include-native` ahead of the gathered set. This is the gate's
      # own `$(COMPAT_CPPFLAGS)` (tools/Makefile.tools), spelled against the
      # installed tree instead of the workspace. sgs uses it; it carries the
      # ELF API headers as well as the type vocabulary.
      sgsCflags = "-I${self}/include-native -I${self}/include -include ${self}/include-native/native_compat.h";

      # The same, minus the ELF API half: for a consumer that links the HOST's
      # libelf and so must not see illumos' <libelf.h>/<gelf.h>. See the
      # `include-sys` note in postInstall above.
      stagedCflags = "-I${self}/include-native -I${self}/include-sys -include ${self}/include-native/native_compat.h";

      # "host ELF": <sys/elf.h> forwarded to the host's <elf.h>, for a consumer
      # that links the host's libelf and so must not also have illumos' ELF
      # types in scope. Mutually exclusive with the staged profile's own
      # <sys/elf.h>, so it has to be searched first.
      hostElfCflags = "-I${self}/include-host-elf";

      # "overlay": the gate's own headers win throughout and this only prepends
      # the repointed few, so it must come BEFORE the consumer's -I flags for
      # the gate tree. `_REENTRANT` is not optional -- without it the gate's
      # <errno.h> declares a plain `extern int errno`, which collides with
      # glibc's thread-local one and fails to link.
      overlayCflags = "-I${self}/include-overlay -D_REENTRANT";

      # `install_compat_src`: the two halves of the libc shim, installed as
      # source because each only means anything compiled against a different
      # set of headers -- `hostSource` against the host libc's, `gateSource`
      # against the gate's with `overlayCflags` prepended. Those are the
      # consumer's own flags, and there is no single such view to pick here.
      srcDir = "${self}/src/libcompat";
      hostSource = "${self}/src/libcompat/compat_host.c";
      gateSource = "${self}/src/libcompat/compat_gate.c";

      # The libc entry points a foreign libc does not have -- assfail()/
      # assfail3() behind ASSERT(), panic(), getexecname(), strtonum(), and
      # link_ver_string. `lib/$(MACH)/libcompat.a` is the built form, for a
      # consumer linking an executable; `supportSource` is for one that needs
      # them position-independent.
      staticLib = "${self}/lib/i386/libcompat.a";
      supportSource = "${self}/src/libcompat/native_support.c";
    };

  meta = {
    description = "illumos headers and shims for building gate source against a foreign libc";
    platforms = lib.platforms.unix;
    license = lib.licenses.cddl;
  };
})
