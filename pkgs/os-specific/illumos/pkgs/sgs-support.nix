{
  libcompat,
  sgs-libconv,
}:

# The support environment an sgs program needs in order to be built for a host
# whose libc is not illumos': the staged "ELF-y" headers, the NATIVE_BUILD
# shims, and libconv. All three are now packages of their own, so this is only
# the naming of the compile and link profile they add up to -- stated once
# rather than copied into each consumer, which is what every other `*Cflags`
# passthru in this set is for.
#
# It used to BUILD all of that: it ran `tools/sgs/include` and
# `tools/sgs/libconv` under dmake and installed what they left in the build
# directory, plus a copy of `tools/sgs/native`. Every part of that has since
# been overtaken:
#
#  * `tools/sgs/include` staged its header list into its own source directory,
#    which is why it could only be consumed from inside a writable workspace.
#    `tools/libcompat` gathers the same list and INSTALLS it, and the gate
#    patch that taught it to (`tools/sgs: take the staged headers from
#    libcompat`) dropped `include` from `tools/sgs/Makefile`'s SUBDIRS. This
#    file went on running that directory's makefile by hand for a while
#    afterwards.
#
#  * `tools/sgs/native` no longer exists at all: `tools: merge the two
#    `native/` compat trees into `tools/libcompat`` moved it to
#    `tools/libcompat/common`. The `cp -r $SRC/tools/sgs/native` here was
#    copying a path the patch stack deletes.
#
#  * `tools/sgs/libconv` is `sgs-libconv`'s build-platform arm -- literally the
#    same directory, built by the same makefile.
#
# So there is nothing left to build, and this reduces to the two strings its
# only consumer, `mcs`, actually asked for. `-DNATIVE_BUILD` and the
# `libintl.h` force-include are the residue that is genuinely this profile's
# own: they are what `tools/sgs/Makefile.com` puts in CPPFLAGS on top of
# `$(COMPAT_CPPFLAGS)`, and an sgs program built out of `cmd/` gets neither
# from its own makefile.
{
  # `libcompat.sgsCflags` is `-I include-native` ahead of `-I include`,
  # matching the gate's own `$(COMPAT_CPPFLAGS) $(COMPAT_INC_CPPFLAGS)`
  # (tools/Makefile.tools) and `ld.nix`. The shims stand in for headers the
  # host libc lacks; the gathered set is illumos' real headers underneath them.
  # It is `sgsCflags` rather than `stagedCflags` because sgs works in illumos'
  # ELF types throughout and so wants the gathered <libelf.h> and <gelf.h>,
  # which the CTF tools must NOT have; see libcompat.nix.
  cflags = toString [
    "-DNATIVE_BUILD"

    # The sgs sources call gettext(3C) without including <libintl.h>, relying
    # on illumos' <string.h> chain to have pulled it in. glibc's does not.
    "-include"
    "libintl.h"

    libcompat.sgsCflags
  ];

  ldflags = "-L${sgs-libconv}/lib";
}
