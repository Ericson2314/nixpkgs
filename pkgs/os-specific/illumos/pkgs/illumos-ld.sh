#! @shell@
#
# The illumos link-editor, presented as a drop-in `ld` for a GNU toolchain.
#
# Everything here is a translation from what GCC's Solaris specs actually emit
# to what illumos ld(1) actually accepts.  GCC in nixpkgs is configured
# --with-gnu-ld, so its link spec takes the USE_GLD arm of gcc/config/sol2.h and
# hands collect2 a handful of GNU-only flags.  Most of the line is already
# Sun-flavoured (`-G`, `-dy`, `-Qy`, `-Y P,...`, `-z text`, `-pie`) and passes
# through untouched; the cases below are the whole of the difference, measured
# from `gcc -### t.c` and `gcc -shared -fPIC -### t.c`.
#
# Nothing is dropped speculatively.  An option not named here reaches ld and, if
# ld does not know it, the link fails loudly -- which is what should happen.
#
# WHY THIS IS SCOPED TO THE GATE, and what to expect if anyone widens it.
#
# This wrapper is good enough for illumos' own source and is not good enough to
# be the platform's linker for all of nixpkgs.  That was tried; ../default.nix
# says where the decision now lives.  Building the nixbsd `illumos-full` VM with
# `linker = "illumos"` set platform-wide broke six packages in four unrelated
# ways, and they are worth writing down because each is a separate project:
#
#  o	A GNU version script handed to `-M`.  The syntaxes look alike, so
#	configure scripts that probe `ld --help` for "M mapfile" cheerfully pass
#	one.  They do not mean the same thing: a symbol named in a GNU version
#	script that nothing defines is ignored, while one named in a Solaris
#	mapfile is *declared*, and ld emits an undefined entry for it.  libxslt
#	shipped five such symbols and every consumer then failed to link;
#	libxcrypt died outright with "./libcrypt.map: 1: expected a '=', ':',
#	'|', or '@'".  GNU ld has `--undefined-version` for exactly this and
#	illumos ld has no equivalent.
#
#  o	DWARF 5.  GCC 15 emits it by default; illumos ld cannot relocate it, and
#	says so as "invalid offset symbol '.debug_str (section)'" against
#	sections like `.debug_loclists`, which exists only in DWARF 5.  coreutils
#	and openssl both die this way.  The gate never trips it because
#	Makefile.master:495 pins `-gdwarf-4 -gstrict-dwarf` with the comment
#	"Currently this is DWARFv4".  A platform-wide `-gdwarf-4` would probably
#	fix this whole class.
#
#  o	GNU-only options that desynchronise getopt(3) rather than being
#	rejected; see the `--compress-debug-sections` case below for the shape of
#	it.  ncurses hits another one and reports `unrecognized option` naming a
#	path that was an *argument*.
#
#  o	A bug in ld itself, which no wrapper can paper over.  Link a large object
#	-- googletest's `gtest-all.cc.o`, 826K, 553 sections -- into a shared
#	object or an executable with any runpath at all, and relocations come out
#	against a garbage address:
#
#	    ld: fatal: relocation error: R_AMD64_PC32: file gtest-all.o:
#	        symbol .LC3: value 0x652fe4a5136f does not fit
#
#	`-R /a` is enough; it is not length-dependent.  It is not the wrapper's
#	translation, because illumos' own `-R` spelling fails identically.  The
#	value differs on every run with the low bits stable, so it is
#	uninitialised memory, not a layout decision.  Ruled out: `-z now`, `-z
#	text`, `-fno-merge-constants`, `-fno-exceptions`, runpath length, section
#	count (an 1811-section object links fine) and `--dynamic-linker`.  gtest
#	and boost die this way.  This one predates the wrapper entirely -- the
#	`ld` derivation is byte-identical with or without it -- and needs
#	debugging in usr/src/cmd/sgs, not here.

set -eu -o pipefail

# dmake sets SGS_SUPPORT for .KEEP_STATE so that ld records dependencies through
# libmakestate.so.1.  We have no such support library, and ld's dlopen() of it
# uses illumos-only mode flags that glibc rejects outright ("invalid mode
# parameter").
unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64

# illumos ld parses its command line with getopt(3), and glibc's getopt permutes
# argv so that non-option arguments end up after the options.  `ld a.o -L/x
# -lfoo` is silently reordered into `ld -L/x -lfoo a.o`, so every archive is
# searched before the objects that reference it, no archive member is ever
# extracted, and the link fails with "symbol referencing errors" naming symbols
# plainly present in the archive.
export POSIXLY_CORRECT=1

argv=("$@")
args=()
n=${#argv[@]}
i=0

# A relocatable link (`ld -r`, as usr/src/lib/crt does to combine mach-crt1.o
# and common-crt.o) has no interpreter, and illumos ld says so outright:
#
#     ld: fatal: relocatable object option (-r, --relocatable, -z type=reloc)
#         and -I are incompatible
#
# bintools-wrapper adds `-dynamic-linker` from NIX_DYNAMIC_LINKER whenever its
# own `checkLinkType` calls the link dynamic, and `-r` does not make it say
# otherwise. GNU ld ignores the pair in that combination; illumos ld -- where
# the GNU spelling is an alias for `-I` -- refuses it. So find out first, and
# drop the option below.
relocatable=0
for a in "$@"; do
	case "$a" in
	-r | --relocatable)
		relocatable=1
		;;
	esac
done

while (( i < n )); do
	a=${argv[i]}
	next=${argv[i+1]-}

	case "$a" in
	# LTO.  illumos ld has no plugin interface at all.
	-plugin)
		i=$(( i + 1 ))
		;;
	-plugin-opt=*)
		;;

	# GNU build-ID notes.  illumos ld emits no notes at all; `readelf -n` on
	# an illumos-linked object prints nothing.
	--build-id | --build-id=*)
		;;

	# illumos ld builds .eh_frame_hdr unconditionally and has no switch for
	# it.
	--eh-frame-hdr)
		;;

	# Compressed debug sections are a BFD feature; illumos ld has none.
	# nixpkgs emits this whenever a derivation sets `separateDebugInfo`,
	# which the gate's commands do (`debug` is one of their outputs), so it
	# is not rare -- and its failure mode is thoroughly misleading. illumos
	# ld does not reject it as an unrecognized option; it half-swallows it,
	# desynchronising getopt(3) so that the argument of whatever `-rpath`
	# came *before* it is left standing alone:
	#
	#     ld: fatal: unrecognized option '/nix/store/...-foo/lib'
	#
	# naming a path that is perfectly valid and an option that was never
	# passed. Alone, or with no -rpath before it, the same flag is silently
	# tolerated -- which is why this only ever showed up on the commands.
	--compress-debug-sections | --compress-debug-sections=*)
		;;

	# BFD emulation name (`-m elf_x86_64_sol2`).  illumos ld has no -m; the
	# ELF class and machine come from the input objects.
	-m)
		i=$(( i + 1 ))
		;;

	# `-z relro` is BFD-only.  illumos ld rejects it with "option -z has
	# illegal argument 'relro'" rather than "unrecognized option", so
	# bintools-wrapper's probe for unsupported -z flags does not catch it and
	# it has to be dropped here.  Every other -z argument is passed on.
	-z)
		case "$next" in
		relro | norelro)
			i=$(( i + 1 ))
			;;
		*)
			args+=("$a")
			;;
		esac
		;;

	# GCC spells the interpreter `-dynamic-linker=PATH`.  illumos ld does
	# accept the GNU name, but only in its double-dash form: `-d` takes an
	# argument in ld's getopt string, so a single-dash `-dynamic-linker` is
	# eaten as `-d ynamic-linker` and fails with "option -d has illegal
	# argument 'ynamic-linker'".
	-dynamic-linker=*)
		if (( ! relocatable )); then
			args+=(--dynamic-linker "${a#-dynamic-linker=}")
		fi
		;;
	-dynamic-linker | --dynamic-linker)
		if (( relocatable )); then
			i=$(( i + 1 ))
		else
			args+=(--dynamic-linker)
		fi
		;;

	# lib/Makefile.lib builds DYNFLAGS for the compiler driver
	# (-Wl,-h$(SONAME), -Wl,-M$(MAPFILE)), but these libraries are linked by
	# ld directly.  ld strips a bare `-Wl,` prefix itself
	# (cmd/sgs/libld/common/util.c:539), which is why the single-argument
	# forms have always worked; what it does not do is split on the comma, so
	# the multi-argument form arrives as one token.
	-Wl,*)
		IFS=, read -r -a parts <<< "${a#-Wl,}"
		args+=("${parts[@]}")
		;;

	*)
		args+=("$a")
		;;
	esac

	i=$(( i + 1 ))
done

# Set ILLUMOS_LD_DEBUG to anything non-empty to see both sides of the
# translation.  Worth having permanently: when a link fails here the message
# comes from ld, which reports what *it* was given, and the interesting question
# is always what the caller gave *us* -- a question nothing else in the build can
# answer, because collect2 does not print the ld line and dmake does not print
# the collect2 one.
if [ -n "${ILLUMOS_LD_DEBUG-}" ]; then
	printf 'illumos-ld: in :%s\n' "$(printf ' %q' "$@")" >&2
	printf 'illumos-ld: out:%s\n' \
	    "$(printf ' %q' ${args[@]+"${args[@]}"})" >&2
fi

exec @ld@ ${args[@]+"${args[@]}"}
