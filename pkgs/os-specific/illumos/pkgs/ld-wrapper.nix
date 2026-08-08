{ buildPackages }:

# illumos' link-editor, wrapped for use as `$(LD)` in a Nix build. This is the
# single wrapper -- libc, libm, libpthread, the sgs libraries and ld.so.1 all
# go through it.
#
# It names `buildPackages.illumos.ld` explicitly because splicing rewrites
# `nativeBuildInputs` but not string interpolation: a bare `${ld}` here would
# refer to the illumos-hosted link-editor, which is not runnable on the build
# machine.
#
# Two adjustments, and only two -- POSIXLY_CORRECT is *not* among them, because
# `ld`'s own bin/ld already sets it (see the comment there; it is a property of
# running the binary at all, not of any particular caller).
#
#  o	SGS_SUPPORT is unset. dmake sets it for .KEEP_STATE so that ld records
#	dependencies through libmakestate.so.1; we have no such support library,
#	and ld's dlopen() uses illumos-only mode flags that glibc rejects
#	outright ("invalid mode parameter").
#
#  o	`-Wl,a,b` is split into `a b`. lib/Makefile.lib builds DYNFLAGS for the
#	compiler driver (-Wl,-h$(SONAME), -Wl,-M$(MAPFILE)), but these libraries
#	have to be linked by ld directly -- GNU ld via collect2 cannot parse
#	`$mapfile_version 2` mapfiles and rejects -Bdirect. Rewriting here keeps
#	DYNFLAGS itself untouched.
#
#	ld does strip a bare `-Wl,` prefix itself (cmd/sgs/libld/common/util.c:539),
#	which is why the single-argument forms `-Wl,-hlibc.so.1` and
#	`-Wl,-M<file>` have always worked without help. What it does *not* do is
#	split on the comma, so the multi-argument form arrives as one token. The
#	loop below is a no-op on any argument that is not `-Wl,`-prefixed, which
#	is what makes one wrapper safe for every caller.
buildPackages.writeShellScript "illumos-ld" ''
  unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
  args=()
  for a in "$@"; do
    case "$a" in
      -Wl,*)
        IFS=, read -r -a parts <<< "''${a#-Wl,}"
        args+=("''${parts[@]}")
        ;;
      *)
        args+=("$a")
        ;;
    esac
  done
  exec ${buildPackages.illumos.ld}/bin/ld "''${args[@]}"
''
