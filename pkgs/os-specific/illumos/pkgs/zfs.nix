{
  mkDerivation,

  headers,

  libzfs,
  libzfs_core,
  libzutil,
  libuutil,
  libumem,
  libnvpair,
  libsec,
  libidmap,
  libcmdutils,
  # <libshare.h> for the declarations `zfs share` uses; the implementation is
  # dlopened by libzfs, not linked. See libshare-headers.nix.
  libshare-headers,
}:

# zfs(8) -- datasets: create, destroy, snapshot, clone, send, receive, mount,
# and the whole property interface.
#
# Built by hand rather than through cmd/zfs/Makefile, the same way ipadm and
# zpool are: three .c files, one link. The consequence, as there, is no CTF in
# the binary.
#
# What is *not* built here, and is a real gap rather than an omission by
# accident, is the `mount`/`umount` links. cmd/zfs/Makefile installs the same
# binary as /etc/fs/zfs/mount and /usr/lib/fs/zfs/mount, which is how mount(8)
# and the mountall path reach ZFS -- `mount -F zfs` execs the helper for the
# filesystem type. `zfs mount` works without them; `mount -F zfs` and boot-time
# mounting of a non-legacy dataset do not. Adding them means deciding where
# /etc/fs lives in this image, which is the image builder's business.
mkDerivation {
  pname = "zfs";
  path = "usr/src/cmd/zfs";

  extraPaths = [
    # zfs_prop.h / zfs_deleg.h, the property and delegation tables shared with
    # the kernel; the code behind them is already inside libzfs.
    "usr/src/common/zfs"

    # <sys/fs/zfs.h> and <sys/zfs_project.h>.
    "usr/src/uts/common/fs/zfs"

    # <directory.h> -- libidmap's directory-service interface, which
    # `zfs allow` uses to turn a name into a SID. libidmap's `dev` output does
    # not carry it (its own Makefile installs it, and we build the amd64
    # subdirectory directly), so take it from the tree.
    "usr/src/lib/libidmap/common"
  ];

  buildInputs = [
    headers
    libzfs
    libzfs_core
    libzutil
    libuutil
    libumem
    libnvpair
    libsec
    libidmap
    libcmdutils
    libshare-headers
  ];

  # `zfs_main.c` calls `(void) fprintf(fp, msg)` with a gettext()ed string in
  # several places, which nixpkgs' `format` hardening turns into an error
  # (`-Werror=format-security`). Upstream builds with `-errwarn=%all` and does
  # not see this, because Studio has no such check and the gate's gcc flags do
  # not include it. Nothing here takes a format string from an untrusted
  # source.
  hardeningDisable = [ "format" ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    $CC -O2 -o zfs \
      zfs_main.c zfs_iter.c zfs_project.c \
      -I"$SRC/common/zfs" \
      -I"$SRC/uts/common/fs/zfs" \
      -I"$SRC/lib/libidmap/common" \
      -DTEXT_DOMAIN=\"SUNW_OST_OSCMD\" \
      -D_REENTRANT \
      -Wno-error \
      -lzfs_core -lzfs -luutil -lumem -lnvpair -lsec -lidmap -lzutil -lcmdutils

    runHook postBuild
  '';

  # /usr/sbin/zfs is a symlink to ../../sbin/zfs on a real system, because
  # mounting datasets has to work before /usr is mounted. Ship it in `sbin`
  # only; nothing here has a split /usr.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/sbin"
    cp zfs "$out/sbin/zfs"
    chmod 755 "$out/sbin/zfs"

    runHook postInstall
  '';

  meta = {
    description = "illumos ZFS dataset administration tool";
    mainProgram = "zfs";
  };
}
