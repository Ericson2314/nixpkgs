{
  lib,
  runCommand,
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
# compat_host.c / compat_gate.c are the function half -- the entry points a
# foreign libc simply does not have. They are split in two because they must be
# compiled against different headers, which is also why compat_priv.h between
# them may name no libc type at all.
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

  self = runCommand "illumos-compat-${version}"
  {
    inherit commonHeaders intelHeaders;

    # The flags each profile needs, so that a consumer names the profile rather
    # than re-deriving the -I/-include incantation. These were copied by hand
    # into every consumer before, which is exactly how they drift apart.
    passthru = {
      # "staged": host libc wins, illumos ELF headers layered on top.
      stagedCflags = "-I${self}/include -include ${self}/include/native_compat.h";

      # "gate": the gate's headers win; this only prepends the overlay, so it
      # must come *before* the consumer's own -I flags for the gate tree.
      # `_REENTRANT` is not optional -- without it the gate's <errno.h> declares
      # a plain `extern int errno`, which collides with glibc's thread-local one
      # and fails to link.
      overlayCflags = "-I${self}/include-overlay -D_REENTRANT";

      # The two halves of libcompat, to be compiled by the consumer.
      hostSource = "${self}/src/compat_host.c";
      gateSource = "${self}/src/compat_gate.c";
      srcDir = "${self}/src";
    };

    meta = {
      description = "illumos headers and shims for building gate source against a foreign libc";
      maintainers = with lib.maintainers; [ ericson2314 ];
      platforms = lib.platforms.unix;
      license = lib.licenses.cddl;
    };
  }
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

    # <sys/inttypes.h> is illumos' spelling of <inttypes.h>. The real one drags
    # in <sys/int_types.h>, which redefines the whole intN_t family and would
    # collide with the host's <stdint.h>, so forward to the host's instead.
    # ...and the same for <sys/stdint.h>, which <sys/multiboot2.h> includes.
    for h in inttypes stdint; do
      printf '#include <%s.h>\n' "$h" > "$out/include/sys/$h.h"
    done

    # The "gate" profile: the header overlay, and the two halves of libcompat.
    #
    # Shipped as sources rather than as a built library because compat_gate.c
    # has to be compiled against the *consumer's* view of the gate headers --
    # the same -I flags and the same feature-test macros -- and there is no one
    # such view to pick here. Its consumers already have all of that set up.
    cp -r ${./overlay} "$out/include-overlay"
    chmod -R u+w "$out/include-overlay"

    mkdir -p "$out/src"
    cp ${./compat_host.c} "$out/src/compat_host.c"
    cp ${./compat_gate.c} "$out/src/compat_gate.c"
    cp ${./compat_priv.h} "$out/src/compat_priv.h"
  ''
;
in
self
