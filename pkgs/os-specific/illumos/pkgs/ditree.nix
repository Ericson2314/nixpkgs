{
  lib,
  mkDerivation,

  headers,
  libdevinfo,
}:

# ditree(1) -- walk the devinfo tree and print every node's driver binding and
# state.
#
# Not an illumos program: a few dozen lines written here against libdevinfo,
# because the question it answers keeps coming up and nothing packaged answers
# it. devfs shows only *attached* nodes, so a driver that binds and then fails
# attach(9E) looks exactly like a device that is not present:
# /devices/pci@0,0/ contains nothing but isa@1 either way, and no diagnostic
# is emitted anywhere userland can see it.
#
# libdevinfo sees the whole tree, hidden nodes included, so it separates the
# two. The `DINFOFORCE` snapshot is the point -- it forces an attach of nodes
# that are currently detached, so the failure is provoked while we are looking
# rather than having happened silently during boot.
#
# prtconf(8) is the real tool for this, but it is a much larger program with a
# much larger dependency tail; this is the part that matters for bring-up.
# Retire it when prtconf is packaged.
mkDerivation {
  pname = "ditree";
  noLibc = false;

  # No illumos source subtree -- the C is here. `path` still has to name
  # something in the gate for the shared mkDerivation plumbing, so this points
  # at the library it uses; nothing from that directory is compiled.
  path = "usr/src/lib/libdevinfo";

  buildInputs = [
    headers
    libdevinfo
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -o ditree ${./ditree.c} -ldevinfo
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ditree $out/bin/ditree
    chmod 755 $out/bin/ditree
    runHook postInstall
  '';

  meta = {
    description = "Print the illumos devinfo tree with per-node driver binding and state";
    mainProgram = "ditree";
  };
}
