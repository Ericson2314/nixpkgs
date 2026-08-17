{
  mkDerivation,
  uts-common,
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

    outputs = [
      "out"
      # The DWARF split out of `unix` and `genunix` by uts-common.nix's
      # postFixup.
      "debug"
      "buildtree"
    ];

    # See the identical note in kmod.nix: the kernel's DWARF is split by
    # `strip-dwarf.py`, never by stdenv's separate-debug-info.sh, because GNU
    # objcopy destroys these objects. On `unix` it also reorders the allocatable
    # sections and takes the multiboot header out of the first 8K, so nothing
    # would boot the result.
    illumosOwnDebugOutput = true;

    buildPhase = ''
      runHook preBuild

      local flagsArray=()
      concatTo flagsArray makeFlags makeFlagsArray

      # `def.targ` rather than `def`: `def` expands to $(DEF_DEPS), whose rule
      # (uts/Makefile.targ:263) re-invokes $(MAKE) with BUILD_TYPE set, and dmake
      # does not carry every command-line macro across that extra level -- MACH
      # survives, NATIVE_MACH does not. Setting BUILD_TYPE ourselves and asking
      # for the inner target keeps everything at one make level. DBG64 is what
      # DEF_BUILDS64 selects for a non-release build (uts/Makefile.uts:69).
      export BUILD_TYPE=DBG64

      # Several header directories under uts/common have generated members:
      # sys/priv_names.h and friends come from awk (uts/common/sys/Makefile:1386),
      # rpc/rpc_sztypes.h and friends from rpcgen (uts/common/rpc/Makefile:110).
      # A real build has them installed into /usr/include long before the kernel
      # is compiled; here the kernel reads them straight out of the tree. `all_h`
      # is exactly the generated set and installs nothing.
      for mk in common/*/Makefile; do
        grep -q '^all_h:' "$mk" || continue
        ( cd "$(dirname "$mk")" && make "''${flagsArray[@]}" all_h )
      done

      # assym.h and kdi_assym.h, consumed by the assembly in both unix and
      # genunix.
      ( cd i86pc/genassym && make "''${flagsArray[@]}" def.targ )

      # common/os/priv_const.c is generated from the same awk script and table.
      # uts/intel/Makefile:73 owns the rule and hangs it off a `genunix` target;
      # upstream reaches it through uts/Makefile's `.prereq` machinery, which is
      # part of the parallel-build scaffolding we are not using.
      # Ask for the file, not for uts/intel/Makefile's `genunix:` target: genunix
      # is also a $(KMODS) entry there, so the name matches a second rule that
      # recurses into intel/genunix and rebuilds the whole module.
      ( cd intel && make "''${flagsArray[@]}" "$SRC/uts/common/os/priv_const.c" )

      # genunix first: uts/i86pc/unix/Makefile:52 links unix against
      # ../../intel/genunix/$(OBJS_DIR)/libgenunix.so.
      #
      # IPCTF_TARGET= drops the ipctf.a step (uts/Makefile.uts:337): genunix
      # normally has the whole ip driver's CTF merged into it so that networking
      # types are available to uniquify other modules against. That is a
      # size/space optimisation for the rest of the kernel, not something genunix
      # or unix needs to link, and building it would drag in all of intel/ip.
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

      # The identity-mapped entry stub. It is already embedded in `unix` -- the
      # link uses `-e dboot_image`, and uts/i86pc/unix/Makefile:181 turns it into
      # an object with elfextract -- but it is useful to have on its own.
      cp i86pc/unix/dboot/debug64/dboot "$out/platform/i86pc/kernel/amd64/dboot"

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
      mkdir -p "$buildtree"
      cp -a "$SRC/.." "$buildtree/usr"

      runHook postInstall
    '';
  }
)
