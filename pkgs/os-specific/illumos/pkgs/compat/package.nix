{
  lib,
  stdenvNoCC,
  filterSource,
  version,
}:

# The headers and shims that let illumos source compile and link against a
# foreign libc, for the programs the build needs to *run on the build host*
# rather than ship to the target.
#
# This is the same trick tools/sgs/include and tools/sgs/native play for the
# native link-editor: rather than putting the whole illumos header tree on the
# include path (where its <sys/types.h>, <sys/stat.h> and <sys/inttypes.h>
# collide head-on with glibc's), stage an explicit list of "ELF-y" headers that
# glibc has no equivalent for, and force-include a compat header supplying the
# vocabulary those staged headers assume.
#
# Judgement is needed when adding to the list: prefer letting glibc win, and
# only stage a header when glibc genuinely has no counterpart -- or, as with
# <sys/elf.h>, when glibc's counterpart refuses to compile at all ("This header
# is unsupported on x86-64").
#
# This is a pile of text with no compiler and no platform of its own, so it
# takes the headers straight from the filtered source rather than depending on
# the `headers` package, which is illumos-hosted and cannot be evaluated for
# the build platform.
#
# It was once called `onbld-native`, which was doubly wrong: there is no
# illumos-hosted counterpart for it to be the "native" variant of (an illumos
# host needs none of this -- its libc *is* illumos'), and it is not a build at
# all, so it has no platform for a suffix to name. The staged file
# `native_compat.h` keeps its name because that is upstream's, matching
# tools/sgs/native/native_compat.h and tools/ctf/native/native_compat.h.
#
# It was then called `onbld-compat`, which was too narrow: the same problem --
# "illumos source, foreign libc" -- turns up well outside onbld, and solving it
# in a fourth private copy each time is how you end up with four subtly
# different answers. Hence plain `compat`, with the *BSDs' equivalents as the
# model: NetBSD's tools/compat and FreeBSD's tools/build + libegacy.
#
# There are two distinct profiles here, and conflating them does not work:
#
#  * "staged" (include/) layers a hand-picked subset of illumos headers on top
#    of the host's. The host libc wins for everything it has, and
#    native_compat.h supplies the illumos type vocabulary those staged headers
#    assume. Used by the small onbld ELF tools.
#
#  * "gate" (include-overlay/) is the opposite: the gate's own header tree wins
#    throughout, and the host supplies only the implementation underneath.
#    Needed by anything that wants illumos' real headers -- a filesystem's
#    on-disk format, say -- where the staged subset is nowhere near enough.
#    Layering the staged profile underneath *breaks* this one: the gate's own
#    <sys/types.h> is then in play, and native_compat.h's typedefs collide with
#    it head-on.
#
# The overlay is small on purpose. Each file is there because the gate's
# declaration and the host's implementation disagree in a way that cannot be
# papered over at link time; see the comment at the top of each for which
# disagreement it settles.
#
# compat_host.c is the function half -- the entry points a foreign libc simply
# does not have. Its other half, compat_gate.c, lives in `mkfs-ufs`, which is
# its only consumer; the two are split because they must be compiled against
# different headers, which is also why compat_priv.h between them may name no
# libc type at all. That header stays here, since both sides include it.
let
  commonHeaders = [
    "elf.h"
    "elftypes.h"
    "elf_386.h"
    "elf_amd64.h"
    "elf_SPARC.h"
    "elf_notes.h"
    "isa_defs.h"
    "feature_tests.h"
    "ccompile.h"
    "note.h"
    # mbh_patch.c walks the multiboot 1 and 2 headers of the image it patches.
    "multiboot.h"
    "multiboot2.h"
    # Pure macros, no types. glibc has a <sys/queue.h> but not the BSD *_SAFE
    # variants that vtfontcvt.c uses.
    "queue.h"
    # <sys/multiboot.h> uses caddr32_t. See the sed below.
    "types32.h"
    # <sys/queue.h> pulls these two in for __containerof.
    "containerof.h"
    "stddef.h"
  ];

  # <sys/machtypes.h> is per-ISA; the rest of the list is machine-independent.
  intelHeaders = [ "machtypes.h" ];

  src = filterSource {
    pname = "illumos-compat";
    path = "usr/src/uts/common/sys";
    extraPaths = [ "usr/src/uts/intel/sys" ];
  };

  # `stdenvNoCC.mkDerivation` with an explicit `buildCommand`, which is exactly
  # what `runCommand` expands to -- but written out so the fixed point is
  # available. The flags below name this derivation's own store path, and
  # `runCommand` is not the fixed-point form, so reaching them through
  # `runCommand` means `let self = runCommand { passthru = "${self}"; }`: the
  # knot tied by hand, working only because Nix is lazy. `finalAttrs` is what
  # stdenv provides for precisely this.
  #
  # `enableParallelBuilding` and `passAsFile = [ "buildCommand" ]` are
  # runCommandWith's own defaults, restated so this stays the same derivation
  # it was.
in
stdenvNoCC.mkDerivation (finalAttrs: {
  name = "illumos-compat-${version}";

  enableParallelBuilding = true;
  passAsFile = [ "buildCommand" ];

  inherit commonHeaders intelHeaders;

  # The flags each profile needs, so that a consumer names the profile rather
  # than re-deriving the -I/-include incantation. These were copied by hand into
  # every consumer before, which is exactly how they drift apart.
  passthru = {
    # "staged": host libc wins, illumos ELF headers layered on top.
    stagedCflags = "-I${finalAttrs.finalPackage}/include -include ${finalAttrs.finalPackage}/include/native_compat.h";

    # "host ELF": <sys/elf.h> forwarded to the host's <elf.h>, for a consumer
    # that links the host's libelf and so must not also have illumos' ELF types
    # in scope. Mutually exclusive with the staged profile's own <sys/elf.h>, so
    # it has to be searched first; see the comment in host-elf/sys/elf.h.
    hostElfCflags = "-I${finalAttrs.finalPackage}/include-host-elf";

    # "gate": the gate's headers win; this only prepends the overlay, so it must
    # come *before* the consumer's own -I flags for the gate tree. `_REENTRANT`
    # is not optional -- without it the gate's <errno.h> declares a plain
    # `extern int errno`, which collides with glibc's thread-local one and fails
    # to link.
    overlayCflags = "-I${finalAttrs.finalPackage}/include-overlay -D_REENTRANT";

    # The host half of libcompat, to be compiled by the consumer. The gate half
    # is `mkfs-ufs`' own file -- see the comment at the top.
    hostSource = "${finalAttrs.finalPackage}/src/compat_host.c";

    # The libc entry points a foreign libc does not have -- assfail()/assfail3()
    # behind ASSERT(), panic(), getexecname(), strtonum(), and link_ver_string.
    # Compiled into whichever library the consumer already links: libctf for the
    # CTF tools, libconv for the link-editor family.
    #
    # This is usr/src/tools/libcompat/common/native_support.c, the merge of what
    # used to be tools/ctf/native and tools/sgs/native. The name below is the
    # older, CTF-only one, kept because consumers use it; `supportSource` is the
    # same file under a name that does not claim it is CTF-specific. Do not
    # narrow this back to the CTF subset -- libconv needs link_ver_string, which
    # the CTF-only version did not define.
    supportSource = "${finalAttrs.finalPackage}/src/ctf_support.c";
    ctfSupportSource = "${finalAttrs.finalPackage}/src/ctf_support.c";
    srcDir = "${finalAttrs.finalPackage}/src";
  };

  meta = {
    description = "illumos headers and shims for building gate source against a foreign libc";
    maintainers = with lib.maintainers; [ ericson2314 ];
    platforms = lib.platforms.unix;
    license = lib.licenses.cddl;
  };

  buildCommand =
  ''
    mkdir -p "$out/include/sys"
    for h in $commonHeaders; do
      cp "${src}/usr/src/uts/common/sys/$h" "$out/include/sys/$h"
    done
    for h in $intelHeaders; do
      cp "${src}/usr/src/uts/intel/sys/$h" "$out/include/sys/$h"
    done

    # <sys/types32.h> is nothing but int32_t/uint32_t typedefs, but it reaches
    # them through illumos' <sys/int_types.h>, which redefines the whole intN_t
    # family and collides with the host's <stdint.h>. Point it at <stdint.h>
    # instead; the typedefs themselves are unchanged.
    sed -i 's|<sys/int_types\.h>|<stdint.h>|' "$out/include/sys/types32.h"

    cp ${./native_compat.h} "$out/include/native_compat.h"

    # illumos' <synch.h> and <thread.h> over pthreads. The real ones reach
    # <sys/machlock.h>, <sys/time_impl.h> and <sys/int_types.h> -- the whole
    # illumos type system -- which collides head-on with the host libc's. The
    # gate code here that uses the Solaris threads API (lib/mergeq, reached by
    # libctf) maps onto pthreads directly.
    #
    # Copied from usr/src/tools/ctf/native, the tree the CTF packages are being
    # moved off; this is where those shims live now.
    cp ${./staged/synch.h} "$out/include/synch.h"
    cp ${./staged/thread.h} "$out/include/thread.h"

    # <sys/inttypes.h> is illumos' spelling of <inttypes.h>. The real one drags
    # in <sys/int_types.h>, which redefines the whole intN_t family and would
    # collide with the host's <stdint.h>, so forward to the host's instead.
    # ...and the same for <sys/stdint.h>, which <sys/multiboot2.h> includes.
    for h in inttypes stdint; do
      printf '#include <%s.h>\n' "$h" > "$out/include/sys/$h.h"
    done

    # The "gate" profile: the header overlay, and the host half of libcompat.
    #
    # Shipped as source rather than as a built library because it has to be
    # compiled against the *consumer's* view of the headers -- the same -I
    # flags and the same feature-test macros -- and there is no one such view
    # to pick here. Its consumers already have all of that set up.
    cp -r ${./host-elf} "$out/include-host-elf"
    chmod -R u+w "$out/include-host-elf"

    cp -r ${./overlay} "$out/include-overlay"
    chmod -R u+w "$out/include-overlay"

    mkdir -p "$out/src"
    cp ${./compat_host.c} "$out/src/compat_host.c"
    cp ${./staged/ctf_support.c} "$out/src/ctf_support.c"
    cp ${./compat_priv.h} "$out/src/compat_priv.h"
  ''
  ;
})
