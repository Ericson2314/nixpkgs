{
  lib,
  stdenvNoCC,
  runtimeShell,
  binutils-unwrapped,
  ld,
}:

# The unwrapped binary utilities for illumos: GNU binutils everywhere except the
# link-editor, which is illumos' own.
#
# Only `ld` is substituted, and only `ld` needs to be. GNU `as`, `ar`, `nm`,
# `objcopy`, `ranlib` and `strip` all understand illumos objects perfectly well
# -- they are ordinary ELF. What GNU ld cannot do is parse illumos
# `$mapfile_version 2` mapfiles, or accept `-Bdirect`, which is essentially
# every link in the gate; and what nothing but the gate's own ld can produce is
# the `.SUNW_*` sections the illumos runtime linker expects.
#
# This is the *unwrapped* half, in the nixpkgs sense: it is what
# `wrapBintoolsWith` wraps. ../default.nix substitutes it into the `cc` of every
# stdenv in this scope, so the gate reaches it through the ordinary cc-wrapper
# -> bintools-wrapper chain rather than through an `LD=` make macro threaded by
# hand through the makefiles. Nothing here knows about store paths for libc,
# rpaths or hardening flags -- that is the wrapper's job.
#
# Scoped to this package set on purpose, and NOT installed as the platform's
# linker in ../../../../lib/systems/default.nix. See ../default.nix for what
# happened when it was: illumos ld is what the gate needs and what the rest of
# nixpkgs cannot use.
#
# Both arguments are passed explicitly by ../default.nix; see the comment there
# for why neither default is right. `ld` is the link-editor that runs on the
# machine doing the build (see ld.nix on why there is one attribute and not
# two), and `binutils-unwrapped` is the cross binutils of the same stage --
# host is this machine, target is illumos -- which is why its programs already
# carry the `x86_64-unknown-solaris2.11-` prefix bintools-wrapper looks for.

let
  inherit (binutils-unwrapped) targetPrefix;
in

stdenvNoCC.mkDerivation {
  pname = "${targetPrefix}illumos-bintools";
  inherit (binutils-unwrapped) version;

  dontUnpack = true;

  strictDeps = true;

  # `ld` is interpolated into the script rather than taken from PATH: this is
  # invoked by collect2, which has its own idea of PATH, and by gate makefiles
  # as `$(LD)`.
  ldScript = ./illumos-ld.sh;

  shell = runtimeShell;
  ldProg = "${ld}/bin/ld";

  # ld.bfd and ld.gold are deliberately not carried over. A build that reaches
  # for `-fuse-ld=bfd` on illumos would silently get a link GNU ld cannot
  # actually complete correctly; better that the flag find nothing.
  buildCommand = ''
    mkdir -p "$out/bin"

    for f in ${binutils-unwrapped}/bin/*; do
      case "$(basename "$f")" in
        ${targetPrefix}ld | ${targetPrefix}ld.*) ;;
        *) ln -s "$f" "$out/bin/" ;;
      esac
    done

    substitute "$ldScript" "$out/bin/ld" \
      --subst-var shell \
      --subst-var-by ld "$ldProg"
    chmod +x "$out/bin/ld"
    ${lib.optionalString (targetPrefix != "") ''
      ln -s ld "$out/bin/${targetPrefix}ld"
    ''}
  '';

  passthru = {
    inherit targetPrefix;

    # The GNU half is real: bintools-wrapper uses this to decide whether to
    # install its deterministic `strip` wrapper, and `strip` here *is* GNU
    # strip. It says nothing about the link-editor.
    isGNU = true;

    # The link-editor half. Nothing in nixpkgs reads this yet; it is here so
    # that a package which must ask "is this the illumos link-editor?" has a
    # name to ask with, rather than pattern-matching on a store path.
    isSun = true;

    inherit ld;
    inherit binutils-unwrapped;
  };

  meta = {
    description = "GNU binutils with the illumos link-editor in place of GNU ld";
    inherit (binutils-unwrapped.meta) platforms;
    maintainers = with lib.maintainers; [ ericson2314 ];
  };
}
