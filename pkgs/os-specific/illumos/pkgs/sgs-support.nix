{
  lib,
  stdenv,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  perl,

  ld,
}:

# The support environment an sgs program needs in order to be built for a host
# whose libc is not illumos': a staged set of "ELF-y" headers, and libconv.
#
# Both come straight out of `usr/src/tools/sgs`, built by its own makefiles
# under dmake -- this package runs two of that tree's SUBDIRS and installs what
# they produce. It exists only because upstream leaves them in the build
# directory: `tools/sgs/include/Makefile` stages its headers into `.`, and
# `tools/sgs/libconv` builds `libconv.a` for `tools/sgs/ld` to pick up with a
# bare `-L../libconv`. Anything else in the tree that wants them -- mcs(1) --
# has no way to reach them.
#
# This is `usr/src/tools/`, which the standing order in ../default.nix tells us
# to avoid, and legitimately so under its own exemption: what lives here exists
# ONLY here. `tools/sgs/native/native_support.c` and its headers are real
# source with no counterpart under `cmd/`, and `tools/sgs/libconv/Makefile`'s
# trimming (dropping `corenote.o` and `lddstub.o`, which need <sys/procfs.h>
# and `dlinfo(RTLD_DI_ORIGIN)`) is the only statement anywhere of what libconv
# means on a foreign host. The order objects to *duplicating* what nixpkgs
# already expresses; it does not ask us to reinvent this.
#
# Kept apart from `ld` rather than published by it, though `ld` builds exactly
# these on its way to the link-editor. `ld` is the most depended-upon package
# in the set -- libc and every kernel module are downstream of it -- so adding
# a file to its output rebuilds the entire tree. Nothing depends on this
# package except mcs, so it costs one small build instead.
let
  self = mkDerivation {
  pname = "sgs-support";
  path = "usr/src/tools/sgs";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/Makefile.sub"
    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/libconv"
    "usr/src/cmd/sgs/messages"
    "usr/src/cmd/sgs/tools/libconv_mk_report_bufsize.pl"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"

    "usr/src/common/elfcap"
    "usr/src/common/sgsrtcid"

    "usr/src/head"
    "usr/src/uts/common/sys"
    "usr/src/uts/intel/sys"

    "usr/src/lib/libc/inc"
    "usr/src/lib/libdemangle/common"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    perl
  ];

  # Each subdirectory's own makefile, entered in dependency order.
  #
  # Not `make include libconv` through `tools/sgs/Makefile`: `include` is a
  # dmake keyword as well as a directory here, and passing it as a command-line
  # target is silently swallowed -- the staging never runs and `sgsmsg` then
  # dies on a missing <sys/isa_defs.h> from the empty `-I../include`. Nor the
  # whole tree via `install`, which is what `ld` already does: that would build
  # the link-editor a second time to reach two of its by-products.
  #
  # `install` is named explicitly. Neither makefile puts its real work first:
  # `include/Makefile` leads with `sys:` (a bare `mkdir`) and states the staging
  # under `all install:`, so a target-less `make` succeeds having copied
  # nothing. Neither installs anywhere -- `libconv` has `install all:
  # $(LIBRARY)`, and the header rules copy into the build directory -- so this
  # only builds.
  #
  # The recursion is upstream's; only the entry points are named here.
  enableParallelBuilding = false;

  buildPhase = ''
    runHook preBuild

    local flags=()
    concatTo flags makeFlags makeFlagsArray

    for d in include libconv; do
      ( cd "$d" && make "''${flags[@]}" install )
    done

    runHook postBuild
  '';

  makeFlags = [
    # libconv runs the sgsmsg built by tools/sgs to generate its message
    # catalogue, and looks for it under $(ONBLD_TOOLS)/bin/$(MACH). `ld` is the
    # package that builds and installs it.
    "ONBLD_TOOLS=${ld}"

    # illumos' MACH/MACH64 are not uname strings; on x86 they are i386/amd64,
    # and the makefiles index directories with them.
    "MACH=i386"
    "MACH64=amd64"
  ];

  # The staged headers land in `include/` and the archive in
  # `libconv/libconv.a`, both relative to the build directory, because that is
  # where upstream's consumers look for them.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/include" "$out/lib"
    cp -r include/. "$out/include/"
    rm -f "$out/include/Makefile"
    cp libconv/libconv.a "$out/lib/"

    # The shims `tools/sgs/Makefile.com` force-includes. `native_support.c` is
    # already compiled into libconv.a above; these are its header half, and a
    # consumer needs them for the same reason libconv did.
    cp -r "$SRC/tools/sgs/native" "$out/include-native"
    chmod -R u+w "$out/include-native"

    runHook postInstall
  '';

  passthru = {
    # The whole compile profile, named rather than re-derived by each consumer
    # -- the way `compat` does it, and for the same reason: copied by hand into
    # two places is how two places drift apart. This is what
    # `tools/sgs/Makefile.com` puts in CPPFLAGS, which an sgs program compiled
    # against a foreign libc needs and cannot get from its own `cmd/` makefile.
    cflags = toString [
      "-DNATIVE_BUILD"

      # The sgs sources call gettext(3C) without including <libintl.h>, relying
      # on illumos' <string.h> chain to have pulled it in. glibc's does not.
      "-include"
      "libintl.h"
      "-I${self}/include"
      "-I${self}/include-native"
      "-include"
      "${self}/include-native/native_compat.h"
    ];
    ldflags = "-L${self}/lib";
  };

  meta = {
    platforms = lib.platforms.unix;
    # Meaningless for an illumos host: there the headers are just <libelf.h>
    # and friends out of the system, and libconv is the packaged sgs-libconv.
    broken = stdenv.hostPlatform.isSunOS;
  };
}
;
in
self
