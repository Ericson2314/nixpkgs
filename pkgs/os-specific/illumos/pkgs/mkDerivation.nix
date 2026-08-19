{
  lib,
  stdenv,
  stdenvNoCC,
  stdenvNoLibc,
  stdenvLibcMinimal,
  filterSource,
  filterPatches,
  patchesRoot,
  illumosSetupHook,
  make,
  install,
  version,

  # Only forced by packages that opt into `illumosLib` below, so the bootstrap
  # packages that build *these* (headers, cw, ld) can keep using mkDerivation
  # without tying the knot.
  buildPackages,
  cw,
  ld-wrapper,
  headers,
}:

let
  # illumos' own arch(1)/mach(1) report "i386" on x86, not "x86_64", and the
  # lib makefiles shell out to them.
  archStubs = [
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  # The makefile fragments read by every usr/src/lib/* build before it reaches
  # its own Makefile.
  libMakefilePaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
  ];

  # Makefile.master:983 leaves POST_PROCESS_O empty and Makefile.lib:191
  # appends "; $(CTFCONVERT_POST)" to it, so the expanded recipe line starts
  # with a bare `;`, which the shell rejects. Both settings below cure that;
  # the difference is only whether CTF is actually produced.
  #
  # Under `illumosCtf` the macro is restated as just the hook. It has to stay a
  # *reference* rather than being resolved here, because CTFCONVERT_POST is
  # target-conditional -- Makefile.lib:208 sets it to $(CTFCONVERT_O) for
  # $(PICS) and leaves it `:` elsewhere -- so it must expand in each target's
  # own context.
  ctfMakeFlags = [
    "POST_PROCESS_O=$(CTFCONVERT_POST)"
    "POST_PROCESS_SO=$(CTFMERGE_POST)"
  ];

  noCtfMakeFlags = [
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
  ];

  # The build-host ("native") overlay, applied whenever a package is built to run
  # on the builder itself.
  #
  # illumos' own answer to "build this program for the build machine" is
  # usr/src/tools/*, and the thing to notice about those makefiles is what they
  # actually are: `tools/sgs/libelf/Makefile` line 2 is
  #
  #     include $(SRC)/cmd/sgs/libelf/Makefile.com
  #
  # They *include the cmd/ makefile* and then override about forty variables.
  # tools/sgs is not a second copy of the build; it is a variable overlay on
  # the real one. So the overlay can be reproduced exactly -- as command-line
  # macros, which outrank anything the gate makefiles set, and therefore need
  # no include injected into each subdirectory's makefile chain.
  #
  # Assembled here rather than by including a gate makefile because no single
  # gate file *is* this overlay: the settings are split between
  # tools/Makefile.tools and tools/sgs/Makefile.com, and both also carry the
  # onbld proto-area layout (24 ROOTONBLD* variables rooted at
  # tools/proto/root_$(MACH)-nd/opt/onbld, plus their $(INS.file) rules). That
  # layout is precisely what nix replaces with $out, and it is already fought
  # once -- ld.nix has to override ROOTONBLD and ONBLD_TOOLS to reclaim its own
  # output. Inheriting it everywhere would spread that fight to every package.
  #
  # Note this is one list, not a per-package recipe. The alternative was each
  # build-host tool restating the overlay in its own `makeFlags`, which is how
  # the hand-written buildPhases in mcs.nix and friends came about in the first
  # place.
  nativeBuildMakeFlags = [
    # The build machine's spelling of the same thing MACH64 spells for the
    # host, from the same table. Makefile.master:736 derives NATIVE_MACH as
    # $(MACH:amd64=i386) -- i.e. i386 -- so NATIVE_CFLAGS would carry -m32 and
    # a Linux build host would need a 32-bit glibc for what is an ordinary
    # 64-bit host program. tools/ctf/Makefile.ctf.native does the same thing by
    # hand for the CTF tools.
    "NATIVE_MACH=${nativeMach.mach64}"

    # -msave-args is illumos-gcc only; host gcc fails outright with
    #     gcc: error: unrecognized command-line option '-msave-args'
    # This single macro is what stops a cmd/ makefile building on the host.
    "SAVEARGS="

    # Solaris link-editor options that GNU ld rejects. The gate passes these
    # unconditionally; on the build host the host linker sees them.
    "BDIRECT="
    "BLOCAL="
    "BREDUCE="
    "ZDEFS="
    "ZDIRECT="
    "ZIGNORE="
    "ZINTERPOSE="
    "ZLAZYLOAD="
    "ZLOADFLTR="
    "ZNOLAZYLOAD="
    "ZNOLDYNSYM="
    "ZRECORD="
    "ZREDLOCSYM="
    "ZTEXT="
    "ZVERBOSE="
    "ZASSERTDEFLIB="
    "ZGUIDANCE="
    "ZFATALWARNINGS="
    "ZASLR="
    "LDCHECKS="
    "VERSREF="
    "NATIVE_LIBS="

    # Mapfiles describe the Solaris runtime linker's view of a shared object.
    # Nothing on the build host consumes them and GNU ld cannot read them.
    "MAPFILE.NED="
    "MAPFILE.PGA="
    "MAPFILE.NES="
    "MAPFILE.FLT="
    "MAPFILE.NGB="
    "MAPFILE.INT="
    "MAPFILES="
    "DYNFLAGS_MAPFILES="

    # `:` is the no-op command, which is how the gate itself spells "skip this
    # step" -- not an empty value, which would run the rule with no program.
    # A build-host tool carries no illumos CTF and is never stripped by mcs.
    "CTFCONVERT_POST=:"
    "CTFMERGE_POST=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_S_O=:"
    "POST_PROCESS_CC_O=:"
    "POST_PROCESS_A=:"
    "POST_PROCESS_SO=:"
    "POST_PROCESS=:"
    "PROCESS_CTF=:"
    "STRIP_STABS=:"

    # Plain GNU-ld rpath in place of the Solaris runpath handling. $$ORIGIN
    # survives into the binary as $ORIGIN; the doubling is make's escape.
    "DYNFLAGS=$(HSONAME) -Wl,-rpath,'$$ORIGIN'"

    # From tools/Makefile.tools. Its ROOTONBLD* half is deliberately not
    # reproduced (see above), and neither is its `CPPFLAGS=-D_TS_ERRNO`:
    # Makefile.master:585 already has `DTS_ERRNO=-D_TS_ERRNO` inside
    # `CPPFLAGS.master`, so restating it adds nothing -- while forcing CPPFLAGS
    # as a command-line macro OVERRIDES cmd/sgs/Makefile.com:62, which
    # reassigns it precisely to put `-I.` and `-I../common` ahead of the
    # parent's. Every cmd/sgs package then fails on a missing <conv.h>.
    "ELFSIGN_O=$(TRUE)"
    "GSHARED=-_gcc=-shared"

    # STACKPROTECT is the gate's spelling of the same thing nixpkgs spells
    # `hardeningDisable = [ "stackprotector" ]`. Only one of the two should
    # fire; this is the gate-side half, and packages using this overlay should
    # not also set the nixpkgs-side one.
    "STACKPROTECT=none"
  ];

  # The gate's staged headers -- illumos' libc headers, which only make sense
  # for something that will run on illumos. A build-host instance of the same
  # library uses the host's own headers, so this is kept out of the shared list
  # rather than each library asking which instance it is.
  #
  # They must be searched *before* the -I flags individual rules add, not
  # after. Makefile.targ's regex rule adds -I$(LIBCBASE)/../port/regex, and
  # libc keeps a private regex.h there which does not define REG_ESPACE and
  # friends. Arriving via -isystem (as buildInputs do) is too late in the
  # search order; CPPFLAGS.first is placed ahead of everything else.
  illumosLibMakeFlags = [
    "CPPFLAGS.first=-I${headers}/include"
  ];

  libMakeFlags = [
    # The libc_pic.a rule runs `mcs -d -n .SUNW_ctf` to drop the per-object CTF
    # from the archive, since only the shared library is meant to carry it. mcs
    # is an illumos *target* program (cmd/sgs/mcs) with no build-host build, so
    # the step is skipped: the archive keeps a .SUNW_ctf in each member, which
    # costs some space and changes nothing about linking.
    "MCS=:"
    # LDFLAGS.native is $(LDASSERTS) $(BDIRECT) -- Solaris ld options, which
    # GNU ld rejects when linking a native helper program (libc's genassym).
    # Clear just that, not BDIRECT itself: DYNFLAGS also uses $(BDIRECT), and
    # the shared-library links run under illumos ld with -zguidance
    # -zfatal-warnings, which turns a missing -Bdirect into a hard error.
    "LDFLAGS.native="
  ];

  # illumos' MACH/MACH64 are not uname processor strings, and they are not
  # cosmetic: the gate's makefiles index *directories* and file lists with
  # them. Makefile.targ finds libc's complex-arithmetic sources via
  # $(LIBCBASE)/../$(MACH)/fp/%.c -- lib/libc/i386/fp -- and lists like
  # $(LINK_OBJS_$(MACH)) and $($(MACH)_HDRS) simply expand to nothing when
  # MACH is spelled the uname way. So a wrong MACH does not fail loudly; it
  # quietly builds the wrong thing.
  #
  # These reach make as command-line macros (`makeFlags`), never as
  # environment variables. Command-line macros outrank makefile assignments;
  # environment variables do not, so a makefile that assigns MACH itself would
  # win over the environment and lose to these. That difference is the whole
  # point of passing them here rather than in `env`.
  #
  # TARGET_ARCH is deliberately not overridden: the amd64 makefiles set it
  # themselves, and a command-line macro would clobber that.
  #
  # There is no default case. A CPU with no known illumos spelling throws
  # rather than falling back to i386, because the failure mode of guessing is
  # a build that quietly succeeds against the wrong source directories.
  #
  # Passed to a package only when it asks: an `illumosLib` library (whose
  # makefiles index $(MACH)/$(MACH64) source and object directories throughout),
  # or one that opts in with `illumosMach`. MACH is not free to set everywhere,
  # because it also indexes *install* paths: a makefile that installs to
  # $(ROOTLIBDIR64) or $(ROOTONBLD)/bin/$(MACH) moves its output the moment
  # MACH is non-empty. `crt` is the cautionary case -- it installs to $out/lib
  # only because MACH64 is empty for it, and setting MACH64=amd64 relocates
  # values-Xa.o to $out/lib/amd64 while every consumer still names $out/lib.
  #
  # `illumosOnbldMach` is the separate, narrower opt-in for build-host tools
  # that follow the onbld proto layout ($(ROOTONBLD)/bin/$(MACH)); see its own
  # note below. The two are not interchangeable.
  #
  # A function of a platform rather than of nothing, because the gate names the
  # same concept twice: MACH/MACH64 describe what is being built (the host
  # platform) and the NATIVE_* family describes the machine doing the building
  # (the build platform). Same table, different platform plugged in.
  machFor =
    platform:
    let
      cpu = platform.parsed.cpu.name;
      x86 = {
        mach = "i386";
        mach64 = "amd64";
      };
      sparc = {
        mach = "sparc";
        mach64 = "sparcv9";
      };
      table = {
        i386 = x86;
        i486 = x86;
        i586 = x86;
        i686 = x86;
        x86_64 = x86;
        sparc = sparc;
        sparc64 = sparc;
      };
    in
    table.${cpu}
      or (throw "illumos mkDerivation: no illumos MACH/MACH64 spelling is known for CPU '${cpu}'");

  mach = machFor stdenv.hostPlatform;
  nativeMach = machFor stdenv.buildPlatform;

  # The `illumosOnbldMach` note. Most build-host tools here install into
  # $out/bin, and that works only because MACH is empty for them: the onbld
  # rules install to $(ROOTONBLD)/bin/$(MACH), so setting MACH moves `cw` to
  # $out/bin/i386 where nothing looks for it. The tools that genuinely follow
  # the onbld layout (the CTF tools, `elfextract`, `mbh_patch`, `vtfontcvt`,
  # `mcs`, `sgs-support`, native `ld`) say so and get MACH; the rest must not.
  machMakeFlags = [
    "MACH=${mach.mach}"
    "MACH64=${mach.mach64}"
  ];

in

lib.makeOverridable (
  attrsOrFn:
  let
    # Accept both `mkDerivation { ... }` and `mkDerivation (finalAttrs: { ... })`,
    # so a package that needs to name its own output -- `compat` and
    # `sgs-support` both publish `passthru` compile flags containing their store
    # path -- can use the fixed point instead of `let self = mkDerivation {...}`.
    # That idiom ties the knot by hand and only works by laziness; `finalAttrs`
    # is what stdenv provides for it.
    #
    # The attributes this wrapper reads to configure *itself* -- `noCC`,
    # `noLibc`, `libcMinimal`, `path`, `pname`, `illumosLib`, `illumosCtf` and
    # the rest -- are consulted to choose the stdenv, before any derivation
    # exists. They cannot come from the fixed point, and asking for one is a
    # cycle rather than a subtle bug, so the probe below makes it say so.
    # Everything else is free to use `finalAttrs`: the function is applied a
    # second time, with the real fixed point, where the derivation arguments are
    # assembled.
    attrs =
      if lib.isFunction attrsOrFn then
        attrsOrFn (
          throw (
            "illumos mkDerivation: the attributes that select the stdenv"
            + " (noCC, noLibc, libcMinimal, path, pname, illumosLib, ...) are read"
            + " before the derivation exists and cannot depend on finalAttrs"
          )
        )
      else
        attrsOrFn;

    userAttrs = finalAttrs: if lib.isFunction attrsOrFn then attrsOrFn finalAttrs else attrsOrFn;
  in
  let
    stdenv' =
      if attrs.noCC or false then
        stdenvNoCC
      else if attrs.noLibc or false then
        stdenvNoLibc
      # `libcMinimal` names the gate's own bootstrap libc, which only exists for
      # illumos. A build-host instance of the same package links against the
      # host's libc like anything else, so the knob is ignored there rather than
      # each package having to ask which instance it is.
      else if (attrs.libcMinimal or false) && !isNativeBuild then
        stdenvLibcMinimal
      else
        stdenv;

    pname = attrs.pname or (baseNameOf attrs.path);

    # Split DWARF into a `debug` output, the way the rest of nixpkgs does.
    # stdenv only honours `separateDebugInfo` on Linux and illumos; the gate was
    # widened in ../../../stdenv/generic/make-derivation.nix.
    #
    # Restricted to usr/src/cmd/* -- the userland commands -- and deliberately
    # so. The stock hook cannot be used on anything the illumos link-editor
    # links, which is every library here, for two independent and separately
    # measured reasons:
    #
    #  o It sets `-Wa,--compress-debug-sections` in NIX_CFLAGS_COMPILE, and
    #    illumos ld cannot relocate a compressed .debug_info: every relocation
    #    into it fails with "relocation error: R_AMD64_32: file pics/kstat.o
    #    section [6].debug_info: invalid offset symbol '.debug_str (section)'".
    #    These links run under -zfatal-warnings, so libkstat.so.1 and libmd.so.1
    #    simply do not build.
    #
    #  o It keys everything off the GNU build-ID note, and illumos ld emits no
    #    notes at all -- `readelf -n` on the resulting libc.so.1 prints nothing.
    #    So even where the build survives, the hook skips every file and leaves
    #    an empty `debug` output behind.
    #
    # `illumosLib`/`illumosLd` alone would be the obvious predicate for "linked
    # by illumos ld" and is not sufficient: libmd sets `LD=` in its own
    # makeFlags without either flag. So the source directory is the primary
    # signal -- it is also what "a userland command" means -- with `useLd` kept
    # as a second filter for the commands that do declare it (getent).
    #
    # usr/src/cmd/sgs/* is excluded by hand. That is the link-editor's own
    # source tree, and despite living under cmd/ most of it is libraries --
    # rtld (ld.so.1), libelf, libld, libconv and friends -- all linked by
    # illumos ld and so subject to both problems above.
    #
    # The other exclusions:
    #
    #  o The *host* platform must be illumos. `buildPackages.illumos.*` -- `cw`,
    #    `make`, `install`, `ld` -- are Linux binaries built from illumos source
    #    only to run the cross build. They are in the `nativeBuildInputs` of
    #    every illumos derivation including `uts-base` and every `kmod`, so
    #    giving them debug outputs would move the whole kernel's input closure
    #    for no benefit to anyone debugging illumos.
    #
    #  o `noCC` and headers-only packages install no ELF at all, and stdenvNoCC
    #    leaves $OBJCOPY and $READELF unset, so the hook would only print
    #    "variable is empty, skipping" in exchange for an empty extra output.
    #
    #  o `illumosOwnDebugOutput`: the package already has a `debug` output that
    #    it fills itself. This is the kernel -- `uts-base` and `kmod` split
    #    their DWARF with `mcs -x` (uts-common.nix), never with objcopy,
    #    which silently deletes the DT_NEEDED module dependency names along with
    #    `.strtab` and moves `unix`'s multiboot header out of the first 8K. See
    #    commit "illumos: split kernel DWARF into a `debug` output". Their
    #    usr/src/uts/* paths already exclude them here; the marker is kept as an
    #    explicit, greppable statement of intent, because letting a kernel
    #    object reach the stock hook produces a broken module that still looks
    #    fine.
    #
    #    It is a marker attribute stripped from `attrs` below rather than a
    #    plain `separateDebugInfo = false`, because stdenv leaks that argument
    #    into the builder environment: `false` arrives as an empty *but set*
    #    variable, which is not the same derivation as never mentioning it.
    #    Passing it explicitly changed the hash of every kernel object --
    #    exactly what the opt-out exists to prevent.
    #
    # ...and the last consideration, which currently subsumes all of the above.
    #
    # Both problems were stated as "anything the illumos link-editor links",
    # and until ../bintools.nix that excluded the commands, because they alone
    # reached GNU ld through the compiler driver. They no longer do: this
    # package set now links with illumos ld throughout (see the scope in
    # ../default.nix), so the second bullet applies to the commands too and
    # their `debug` outputs would come out empty even where the link survived.
    #
    # It does not merely come out empty. GCC 15 defaults to DWARF 5 and merges
    # string constants; the gate compiles with `-gdwarf-4 -gstrict-dwarf`
    # (Makefile.master:495, DEBUGFORMAT, whose comment says "Currently this is
    # DWARFv4") precisely because its own tools cannot read anything newer, and
    # a command built with the hook's plain `-ggdb` fails to link at all:
    #
    #   ld: fatal: relocation error: R_AMD64_64: file devfsadm.o section
    #       [11].debug_info: invalid offset symbol
    #       '.rodata.str1.1 (merged string section)': offset 0x3e91b
    #
    # So: never, for now. The rest of the predicate is kept rather than deleted
    # -- it is the statement of what would have to become true again, an
    # illumos ld that emits a build-ID note and relocates modern DWARF, for any
    # of this to be worth turning back on.
    wantsDebugInfo =
      false
      && stdenv'.hostPlatform.isIllumos
      && lib.hasPrefix "usr/src/cmd/" (attrs.path or "")
      && !lib.hasPrefix "usr/src/cmd/sgs/" (attrs.path or "")
      && !useLd
      && !(attrs.noCC or false)
      && !(attrs.headersOnly or false)
      && !(attrs.illumosOwnDebugOutput or false);

    # `illumosLib`: opt in to the shared boilerplate for a usr/src/lib/*
    # library -- the common makefile fragments, tools and command-line macros
    # defined above. Deliberately opt-in rather than automatic: the remaining
    # per-library variation (BUILD.SO overrides, STACKPROTECT) is load-bearing
    # and stays in the individual packages.
    isLib = attrs.illumosLib or false;

    # This overlay means one specific thing: "illumos source is being compiled
    # with a GNU toolchain" -- a gcc with no -msave-args, a linker that rejects
    # the Z* options, and no illumos CTF tooling. Both halves of the test are
    # load-bearing, and each covers a case the other gets wrong:
    #
    #   host==build       is false for any cross build, which is what keeps the
    #                     overlay off illumos userland AND off the kernel. On
    #                     its own it is wrong for a NATIVE build on illumos --
    #                     host==build==solaris -- where the real illumos
    #                     toolchain is present and CTF and the Z* options all
    #                     work. That is a plausible thing to want, not a
    #                     hypothetical.
    #
    #   !isIllumos        excludes exactly that case. On its own it is wrong for
    #                     the kernel: `isOS` means "runs in that OS's userland",
    #                     and the kernel runs on bare metal, so `unix` carrying
    #                     hostPlatform.isIllumos = true is strictly wrong today.
    #                     Correcting it -- modelling the kernel as its own
    #                     target, which no other OS in nixpkgs does yet -- would
    #                     silently reclassify the whole kernel as a build-host
    #                     tool and apply this overlay to it.
    #
    #
    # TODO: revisit. This gates the whole overlay on one condition, but the
    # macros in it do not share a rationale, and some may belong on the other
    # test:
    #
    #   o SAVEARGS, the Z* options and the MAPFILE.* set are about the
    #     TOOLCHAIN being GNU. They are wrong to apply wherever illumos' own
    #     compiler and link-editor are in use, whatever is being built.
    #
    #   o POST_PROCESS*, PROCESS_CTF, CTFCONVERT_POST, CTFMERGE_POST and
    #     STRIP_STABS are about the ARTIFACT being a throwaway build tool that
    #     nobody will debug. That stays true on a native illumos build, where
    #     the Z* options above would be perfectly valid.
    #
    # So a native illumos build of a build-host tool arguably wants the second
    # group and not the first. Nothing exercises that combination today, which
    # is why this is one list and not two.
    # Together they are true only when something is built to run on the builder
    # AND the builder is not illumos, which is precisely when the GNU toolchain
    # is in play.
    # Computed from the plain `stdenv` rather than from `stdenv'`: the choice of
    # `stdenv..` below now depends on THIS, because `libcMinimal` is one of the
    # illumos-only knobs a build-host instance must not honour. Every variant
    # shares the same platforms, so the answer is the same either way.
    isNativeBuild = stdenv.hostPlatform == stdenv.buildPlatform && !stdenv.hostPlatform.isIllumos;

    # Link through illumos' own link-editor. On by default for `illumosLib`;
    # a static-only library (libssp_ns) never links anything and turns it off.
    #
    # This adds only the `LD=` macro, not a `nativeBuildInputs` entry. `ld`
    # used to be in both; dropping the PATH entry was verified to leave
    # libc.so.1, libm.so.2, libpthread.so.1 and libc_pic.a bit-identical,
    # because `LD=` names the wrapper by absolute path and nothing here ever
    # resolves a bare `ld` off PATH. That consequence used to be a hazard --
    # the nearest `ld` was GNU ld -- and is no longer one: this scope's stdenv
    # wraps ./bintools.nix (../default.nix), so the link-editor a makefile
    # reaches by any route is the same one this macro names. The macro survives
    # only because cc-wrapper installs it as `x86_64-unknown-solaris2.11-ld`
    # while the gate's default for `$(LD)` is the absolute path /usr/bin/ld;
    # neither spelling is a bare `ld` on PATH.
    #
    # Never on a build-host instance: there is no illumos link-editor in play
    # there, GNU ld is, and the overlay above has already emptied the macros it
    # would choke on.
    useLd = (attrs.illumosLd or isLib) && !isNativeBuild;

    # Produce real CTF rather than stubbing the post-processing out. Opt-in:
    # it needs ctfconvert/ctfmerge on the build host and DWARF in the objects.
    enableCtf = attrs.illumosCtf or false;

    extraPaths = lib.optionals isLib libMakefilePaths ++ attrs.extraPaths or [ ];
    paths = [ attrs.path ] ++ extraPaths;
  in
  stdenv'.mkDerivation (
    finalAttrs:
    {
      pname = "${pname}-illumos";
      inherit version;

      src = filterSource {
        inherit pname extraPaths;
        inherit (attrs) path;
      };

      inherit extraPaths;

      # Pick out just the hunks of the shared patch set that touch this
      # package's own subset of the tree, so that editing an unrelated hunk does
      # not rebuild this package. Set `autoPickPatches = false` to opt out.
      patches =
        lib.optionals (attrs.autoPickPatches or true) (filterPatches { } patchesRoot paths)
        ++ attrs.patches or [ ];

      nativeBuildInputs = [
        illumosSetupHook
        make
        install
      ]
      ++ lib.optionals isLib ([ cw ] ++ archStubs)
      ++ (attrs.extraNativeBuildInputs or [ ]);

      COMPONENT_PATH = attrs.path or null;

      strictDeps = true;

      # Two reasons, one of them a hard requirement:
      #
      #  o stdenv refuses `separateDebugInfo` together with any of
      #    `{dis,}allowed{References,Requisites}` unless `__structuredAttrs` is
      #    set (../../../stdenv/generic/make-derivation.nix). The userland
      #    commands have debug outputs, and the boot archive wants a
      #    `disallowedRequisites` guard so that a header package sneaking into
      #    its closure -- `illumos.libc` is a symlinkJoin whose links point into
      #    24M of `uts-headers` -- is a build failure rather than something
      #    rediscovered by measuring an ISO. The two cannot coexist without
      #    this.
      #
      #  o With plain attrs every attribute is a *string* in the environment,
      #    so `lib.optionalString cond "..."` still sets an (empty) variable
      #    when `cond` is false, and that is a different derivation from not
      #    mentioning it at all. Lists are likewise flattened to
      #    space-separated strings, which is why a `makeFlags` entry could
      #    never contain a space. Both classes of accident simply do not exist
      #    here.
      __structuredAttrs = true;

      # `make -j`. Without this every illumos build is serial, which compounds
      # badly with the `--max-jobs 1` this project builds with: derivations run
      # one at a time AND make is serial inside each, so `--cores N` bought
      # nothing at all across ~90 kmod derivations plus uts-base plus userland.
      #
      # illumos' makefiles are written for `dmake`, not `make -j`, so expect
      # races. `libsec` already has one: `acl_lex.c` reads `acl.h` while it is
      # being regenerated and the tokens near the end vanish --
      # `acl_lex.l:97: error: 'USER_TOK' undeclared`, which reads like a missing
      # include rather than a race. The response to each new one is a per-package
      # `enableParallelBuilding = false` WITH a comment naming the race, as
      # libsec does, not turning this back off wholesale.
      enableParallelBuilding = true;

      meta = with lib; {
        maintainers = with maintainers; [ ericson2314 ];
        platforms = platforms.illumos;
        license = licenses.cddl;
      };
    }
    // lib.optionalAttrs wantsDebugInfo {
      separateDebugInfo = true;
    }
    // lib.optionalAttrs (attrs.headersOnly or false) {
      installPhase = "includesPhase";
      dontBuild = true;
    }
    // (builtins.removeAttrs (userAttrs finalAttrs) [
      "extraNativeBuildInputs"
      "autoPickPatches"
      "patches"
      "extraPaths"
      "illumosLib"
      "illumosLd"
      "illumosCtf"
      "illumosOwnDebugOutput"
      "illumosMach"
      "illumosOnbldMach"
    ])
    # Last, so that these are *prepended* to whatever the package asked for
    # rather than replaced by it.
    #
    # `machMakeFlags` and `nativeBuildMakeFlags` come first so a package can
    # still override any single macro by restating it in its own `makeFlags`.
    // {
      makeFlags =
        lib.optionals (
          isLib || (attrs.illumosMach or false) || (attrs.illumosOnbldMach or false)
        ) machMakeFlags
        ++ lib.optionals isNativeBuild nativeBuildMakeFlags
        ++ lib.optionals isLib (
          libMakeFlags
          ++ lib.optionals (!isNativeBuild) illumosLibMakeFlags
          ++ (if enableCtf then ctfMakeFlags else noCtfMakeFlags)
          ++ lib.optional useLd "LD=${ld-wrapper}"
        )
        ++ (userAttrs finalAttrs).makeFlags or [ ];
    }
  )
)
