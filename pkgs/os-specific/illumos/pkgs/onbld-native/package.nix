{
  lib,
  runCommand,
  filterSource,
  version,
}:

# The staged headers and compat shim that let the small onbld ELF tools --
# elfextract, mbh_patch, vtfontcvt -- compile against a foreign libc.
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
    pname = "onbld-native";
    path = "usr/src/uts/common/sys";
    extraPaths = [ "usr/src/uts/intel/sys" ];
  };
in
runCommand "onbld-native-compat-${version}"
  {
    inherit commonHeaders intelHeaders;
    meta = {
      description = "Staged illumos ELF headers and compat shim for building onbld tools against a foreign libc";
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
  ''
