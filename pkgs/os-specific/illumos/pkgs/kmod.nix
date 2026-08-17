{
  lib,
  mkDerivation,
  uts-base,
  uts-common,
}:

# One loadable kernel module, built on its own out of `uts-base`'s buildtree.
#
# `module` is a directory under usr/src/uts, e.g. "intel/mm" or "i86pc/apix".
# The module's own Makefile knows its class, so `install.targ` puts it in the
# right place under $(ROOT) -- kernel/fs/amd64/specfs,
# platform/i86pc/kernel/drv/amd64/rootnex, and so on. Some also install a
# driver .conf file next to it.
#
# Nothing links a module against its dependencies: uts/Makefile.targ:39 is
# `$(LD) -ztype=kmod $(LDFLAGS) -o $@ $(OBJECTS)` and the `-Nfs/specfs` entries
# in a module's LDFLAGS are *names* that krtld resolves at modload() time. So
# each of these derivations depends on `uts-base` and on nothing else in the
# kernel, however tangled the run-time dependency graph is. Which modules
# actually have to be present together is unix.nix's business.
module:

mkDerivation (
  uts-common
  // {
    pname = "kmod-${lib.replaceStrings [ "/" ] [ "-" ] module}";

    # The module's DWARF, split out by uts-common.nix's postFixup so that what
    # lands in the boot archive is code, relocations and CTF only.
    outputs = [
      "out"
      "debug"
    ];

    # Already unpacked, already patched, and with the generated headers,
    # assym.h and genunix that this module's build needs left in place. Going
    # back to the filtered source would mean redoing all of that ninety times.
    src = uts-base.buildtree;
    autoPickPatches = false;
    patches = [ ];

    buildPhase = ''
      runHook preBuild

      local flagsArray=()
      concatTo flagsArray makeFlags makeFlagsArray

      # Same BUILD_TYPE / `.targ` reasoning as uts-base.nix: keep everything at
      # one make level so that the command-line macros survive.
      export BUILD_TYPE=DBG64

      # IPCTF_TARGET= for the same reason as in uts-base.nix -- it is only ever
      # non-empty for genunix, but intel/ip's own Makefile also mentions it.
      ( cd ${module} && make "''${flagsArray[@]}" IPCTF_TARGET= def.targ )

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      local flagsArray=()
      concatTo flagsArray makeFlags makeFlagsArray
      export BUILD_TYPE=DBG64

      # $(INS) is `install`, which resolves to $(ONBLD)/install.bin -- and the
      # `install` derivation is *cross*-built, so on the build machine the shell
      # falls through to coreutils' install, which has neither -f nor a
      # -s-with-a-directory. Nothing here needs install(1)'s semantics: these are
      # plain file copies into $out. Note the escaped `$`: make, not the shell,
      # has to expand $@/$</$(@D).
      #
      # ROOT is prepended as empty by illumosSetupHook's addIllumosMakeFlags, so
      # it has to be re-set here, after flagsArray, to win.
      flagsArray+=(
        "INS.dir=mkdir -p \$@"
        "INS.file=mkdir -p \$(@D); rm -f \$@; cp \$< \$@"
        "INS.conffile=mkdir -p \$(@D); rm -f \$@; cp \$(SRC_CONFFILE) \$@"
      )

      ( cd ${module} && make "''${flagsArray[@]}" IPCTF_TARGET= "ROOT=$out" install.targ )

      runHook postInstall
    '';
  }
)
