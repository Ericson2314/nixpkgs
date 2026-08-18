{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
}:

# <libshare.h> and the two headers installed beside it (<libshare_impl.h>,
# <scfutil.h>).
#
# Headers only, and that is not a shortcut: `libzfs` does not link libshare.
# `libzfs_impl.h` includes <libshare.h> for the `sa_handle_t` and share-type
# declarations, and `libzfs_mount.c` reaches the implementation through
# `dlopen("libshare.so.1")` and `dlsym` (the `_sa_*` function pointers in
# `libzfs_impl.h`). It has to be that way round -- libshare's own Makefile.com
# links `-lzfs`, so linking it here would be a cycle.
#
# Building the library is therefore a separate question, and only worth
# answering when something wants `zfs share` to work: the plugins under
# lib/libshare/{nfs,smb,autofs} are what would actually have to come with it.
mkDerivation {
  name = "libshare-headers";
  path = "usr/src/lib/libshare";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.msg.targ"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
  ];

  headersOnly = true;

  # install(1) will not create the destination directory itself.
  installPhase = ''
    mkdir -p "$out/include"
    includesPhase
  '';
}
