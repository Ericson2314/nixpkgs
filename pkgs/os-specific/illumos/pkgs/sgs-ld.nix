{ buildPackages }:

# The illumos link-editor, wrapped for use as `$(LD)` in a Nix build.
#
# Two adjustments:
#
#  o	SGS_SUPPORT is unset. dmake sets it for .KEEP_STATE so that ld records
#	dependencies through libmakestate.so.1; we have no such support library,
#	and ld's dlopen() uses illumos-only mode flags that glibc rejects
#	outright ("invalid mode parameter").
#
#  o	`-Wl,a,b` arguments are split into `a b`. lib/Makefile.lib builds
#	DYNFLAGS for the compiler driver (-Wl,-h$(SONAME), -Wl,-M$(MAPFILE)),
#	but the sgs libraries have to be linked by ld directly -- GNU ld via
#	collect2 cannot parse `$mapfile_version 2` mapfiles and rejects
#	-Bdirect. Rewriting here keeps DYNFLAGS itself untouched.
#
#  o	POSIXLY_CORRECT is set. ld parses its command line with getopt(3), and
#	glibc's getopt permutes argv so that every non-option argument ends up
#	*after* the options. Built on illumos that never happens; built on
#	Linux, `ld a.o -L... -lfoo` becomes `ld -L... -lfoo a.o`, so archives
#	are searched before the objects that need them and no member is ever
#	extracted -- the link fails with "symbol referencing errors" for
#	symbols that are plainly in the archive. POSIXLY_CORRECT makes getopt
#	stop permuting. (This affects every use of the native ld, not just the
#	sgs libraries; ld.so.1 links -lc_pic and -lconv, both archives.)
buildPackages.writeShellScript "illumos-sgs-ld" ''
  unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
  export POSIXLY_CORRECT=1
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
  exec ${buildPackages.illumos.ld-native}/bin/ld "''${args[@]}"
''
