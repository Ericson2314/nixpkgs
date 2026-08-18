{
  mkDerivation,
  uts-common,

  buildPackages,
}:

# The i86pc kernel proper: `unix`, `genunix` (plus the `libgenunix.so` stub
# library that everything else links against), and everything a *loadable*
# module needs to be built on its own afterwards.
#
# The loadable modules are not built here; each one is its own derivation, see
# kmod.nix. What keeps them from being fully independent is CTF: every module
# uniquifies its type graph against genunix
# (CTFMERGE_UNIQUIFY_AGAINST_GENUNIX, uts/Makefile.uts:320, which passes
# `-d $(UTSBASE)/intel/genunix/$(OBJS_DIR)/genunix`), and several header
# directories under uts/common have *generated* members. So this derivation
# publishes a second output, `buildtree`, which is the whole patched source
# tree with the products of the steps below left in place: the generated
# headers, i86pc/genassym's assym.h, common/os/priv_const.c and
# intel/genunix/debug64/genunix. A module derivation copies that tree, cds into
# its own directory and links only its own objects
# (uts/Makefile.targ:39 is `$(LD) -ztype=kmod $(LDFLAGS) -o $@ $(OBJECTS)`;
# inter-module dependencies are `-Nfs/specfs` *names* resolved by krtld at
# modload() time, not link-time inputs).
mkDerivation (
  uts-common
  // {
    pname = "uts-base";

    # genassym: built and run right here, and nowhere else.
    #
    # `uts/i86pc/genassym` compiles a program with $(NATIVECC) and *runs* it to
    # emit part of assym.h, so it needs a compiler for the build machine --
    # which is what puts $CC_FOR_BUILD in the environment for Makefile.master's
    # NATIVE* macros. (The struct offsets in assym.h do not come from there:
    # those are $(OFFSETS_CREATE)'s doing, reading the target compiler's CTF.)
    #
    # Unlike the *BSDs there is no genassym shared between multiple packages,
    # just tiny one-off commands that are better built *en passant* inside the
    # package that needs them. There is nothing here to package: `genassym`
    # exists only as `uts/i86pc/genassym` and `uts/i86xpv/genassym`, two
    # per-platform Makefiles with no source of their own, each driving
    # `ml/genassym.c` through its own platform's headers to emit assym.h for
    # THAT tree's configuration. So this is the sanctioned use of `_FOR_BUILD`
    # -- a tool compiled, run once, and discarded within one derivation -- and
    # it belongs to this derivation alone.
    #
    # It used to live in uts-common.nix, which every loadable module also
    # spreads, on the theory that the macro expansion happens while parsing
    # Makefile.master in every uts make. Expansion does not need the compiler
    # to exist; only running the rule does, and only `unix` ever runs it:
    #
    #     $ grep -rn 'MAKE) all.targ' usr/src/uts
    #     i86pc/unix/Makefile:191:      @cd $(DSF_DIR); $(MAKE) all.targ
    #     i86xpv/unix/Makefile:183:     @cd $(DSF_DIR); $(MAKE) all.targ
    #
    # i86xpv is not built here, so `unix` -- this derivation -- is the only
    # consumer. Modules copy the `buildtree` output, which already has assym.h.
    depsBuildBuild = [ buildPackages.stdenv.cc ];

    # genassym.c reaches <sys/cmn_err.h>, whose __KPRINTFLIKE expands to
    # __attribute__((format(cmn_err, ...))). That format archetype exists only in
    # illumos' GCC fork, which here is the *target* compiler; the build-host
    # compiler is stock GCC and rejects it under -Werror=format.
    #
    # This goes through the cc-wrapper rather than CUSERFLAGS because dmake does
    # not survive passing a command-line macro whose value itself contains an '='
    # ("-_gcc=-Wno-format") down to the recursive $(MAKE) that Makefile.targ:263
    # spawns for the build type.
    #
    # -m64: NATIVE_MACH is $(MACH:amd64=i386), i.e. i386, so NATIVE_CFLAGS
    # carries -m32 (Makefile.master:736, :468) and the build host would need a
    # 32-bit glibc to link uts/i86pc/genassym. genassym prints only preprocessor
    # constants -- ml/genassym.c even `#define`s `struct` to a syntax error to
    # keep anyone from reaching for a struct offset -- so the data model does not
    # matter. This has to travel through the cc-wrapper rather than a
    # NATIVE_MACH= macro: both unix and genunix reach assym.h through an FRC rule
    # that re-enters uts/i86pc/genassym with a bare `$(MAKE) all.targ`
    # (uts/i86pc/unix/Makefile:199), and dmake carries MACH across that but not
    # NATIVE_MACH -- so genassym would be rebuilt there, -m32, and fail. The
    # wrapper appends these last, after the -m32.
    NIX_CFLAGS_COMPILE_FOR_BUILD = "-Wno-format -m64";


    outputs = [
      "out"
      # The DWARF split out of `unix` and `genunix` by uts-common.nix's
      # postFixup.
      "debug"
      "buildtree"
    ];

    # See the identical note in kmod.nix: the kernel's DWARF is split with
    # illumos' own `strip` (mcs), never by stdenv's separate-debug-info.sh,
    # because GNU objcopy destroys these objects. On `unix` it also reorders the allocatable
    # sections and takes the multiboot header out of the first 8K, so nothing
    # would boot the result.
    illumosOwnDebugOutput = true;

    buildPhase = ''
      runHook preBuild

      local flagsArray=()
      concatTo flagsArray makeFlags makeFlagsArray

    ''
    # `def.targ` rather than `def`: `def` expands to $(DEF_DEPS), whose rule
    # (uts/Makefile.targ:263) re-invokes $(MAKE) with BUILD_TYPE set, and dmake
    # does not carry every command-line macro across that extra level -- MACH
    # survives, NATIVE_MACH does not. Setting BUILD_TYPE ourselves and asking
    # for the inner target keeps everything at one make level. DBG64 is what
    # DEF_BUILDS64 selects for a non-release build (uts/Makefile.uts:69).
    + ''
      export BUILD_TYPE=DBG64

    ''
    # Several header directories under uts/common have generated members:
    # sys/priv_names.h and friends come from awk (uts/common/sys/Makefile:1386),
    # rpc/rpc_sztypes.h and friends from rpcgen (uts/common/rpc/Makefile:110).
    # A real build has them installed into /usr/include long before the kernel
    # is compiled; here the kernel reads them straight out of the tree. `all_h`
    # is exactly the generated set and installs nothing.
    + ''
      for mk in common/*/Makefile; do
        grep -q '^all_h:' "$mk" || continue
        ( cd "$(dirname "$mk")" && make "''${flagsArray[@]}" all_h )
      done

    ''
    # assym.h and kdi_assym.h, consumed by the assembly in both unix and
    # genunix.
    + ''
      ( cd i86pc/genassym && make "''${flagsArray[@]}" def.targ )

    ''
    # common/os/priv_const.c is generated from the same awk script and table.
    # uts/intel/Makefile:73 owns the rule and hangs it off a `genunix` target;
    # upstream reaches it through uts/Makefile's `.prereq` machinery, which is
    # part of the parallel-build scaffolding we are not using.
    # Ask for the file, not for uts/intel/Makefile's `genunix:` target: genunix
    # is also a $(KMODS) entry there, so the name matches a second rule that
    # recurses into intel/genunix and rebuilds the whole module.
    + ''
      ( cd intel && make "''${flagsArray[@]}" "$SRC/uts/common/os/priv_const.c" )

    ''
    # genunix first: uts/i86pc/unix/Makefile:52 links unix against
    # ../../intel/genunix/$(OBJS_DIR)/libgenunix.so.
    #
    # IPCTF_TARGET= drops the ipctf.a step (uts/Makefile.uts:337): genunix
    # normally has the whole ip driver's CTF merged into it so that networking
    # types are available to uniquify other modules against. That is a
    # size/space optimisation for the rest of the kernel, not something genunix
    # or unix needs to link, and building it would drag in all of intel/ip.
    + ''
      ( cd intel/genunix && make "''${flagsArray[@]}" IPCTF_TARGET= def.targ )

      ( cd i86pc/unix && make "''${flagsArray[@]}" def.targ )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/platform/i86pc/kernel/amd64" "$out/kernel/amd64" "$out/lib"
      cp i86pc/unix/debug64/unix "$out/platform/i86pc/kernel/amd64/unix"
      cp intel/genunix/debug64/genunix "$out/kernel/amd64/genunix"
      cp intel/genunix/debug64/libgenunix.so "$out/lib/libgenunix.so"

    ''
    # The identity-mapped entry stub. It is already embedded in `unix` -- the
    # link uses `-e dboot_image`, and uts/i86pc/unix/Makefile:181 turns it into
    # an object with elfextract -- but it is useful to have on its own.
    + ''
      cp i86pc/unix/dboot/debug64/dboot "$out/platform/i86pc/kernel/amd64/dboot"

    ''
    # The whole tree, source and build products together, for kmod.nix to
    # build individual modules out of. $SRC is usr/src of the unpacked
    # sourceRoot (illumosSetupHook's setIllumosSourceDir); we are currently
    # inside $SRC/uts because COMPONENT_PATH sent us there.
    #
    # A copy rather than a set of hand-picked files: which generated header a
    # given module ends up reading is a property of uts/common/Makefile.files
    # and the module's own -I flags, not something enumerable up front, and
    # getting it wrong fails as a missing type deep in a compile rather than
    # as a missing file.
    #
    # Timestamps do not survive this: Nix normalises every mtime in an output
    # to the epoch. That is harmless and in fact the safe direction -- with
    # generated header and generator equally old, make leaves the header
    # alone, whereas a header that looked *older* than its input would be
    # regenerated in every one of the ninety module builds.
    + ''
      mkdir -p "$buildtree"
      cp -a "$SRC/.." "$buildtree/usr"

      runHook postInstall
    '';
  }
)
