{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# <fm/libtopo.h> and the four headers installed beside it (topo_mod.h,
# topo_hc.h, topo_list.h, topo_method.h).
#
# Headers only, for the same reason as libshare-headers.nix: `libzfs` does not
# link libtopo. `libzfs_impl.h` includes <fm/libtopo.h> for the handle and
# `topo_hdl_t` declarations, and `libzfs_fru.c` reaches the implementation
# through `dlopen("libtopo.so")` -- the FRU (field-replaceable unit) names that
# `zpool status` can print for a failed disk are a fault-management service
# libzfs asks for if it is there and does without if it is not.
#
# So the library itself is only worth building when someone wants those names,
# and it is not small: libtopo drives the whole plugin tree under
# lib/fm/topo/modules.
mkDerivation {
  name = "libtopo-headers";
  path = "usr/src/lib/fm/topo/libtopo";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/fm/Makefile.lib"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
  ];

  dontBuild = true;

  # A plain copy rather than the Makefile's `install_h`. That target is
  # `install_h: $(ROOTFMHDRS)`, and the pattern rule which would build those
  # prerequisites -- `$(ROOTFMHDRDIR)/%: common/%` -- lives in
  # lib/fm/Makefile.targ, which this Makefile does not include: it includes
  # lib/Makefile.targ three directories up. So `install_h` has nothing to make
  # its prerequisites with and quietly installs nothing, which is exactly the
  # failure this package would otherwise ship (an empty `include/fm`, and the
  # missing header rediscovered in libzfs' compile).
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/include/fm"
    cp common/libtopo.h common/topo_mod.h common/topo_hc.h \
      common/topo_list.h common/topo_method.h "$out/include/fm/"

    runHook postInstall
  '';
}
