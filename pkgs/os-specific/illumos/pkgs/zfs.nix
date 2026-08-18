{
  mkDerivation,

  cw,
  ctfconvert,

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
# Driven through usr/src/cmd/zfs/Makefile rather than compiled by hand, for the
# same reason as zpool: that Makefile includes ../Makefile.ctf, and CTF comes
# from the build system rather than from a compiler flag, so a hand-rolled
# `$CC -o zfs *.c` could not have it. See zpool.nix for why `CTF_MODE=link` is
# the mode chosen here.
#
# What is *not* installed here, and is a real gap rather than an omission by
# accident, is the `mount`/`umount` links. cmd/zfs/Makefile's install target
# drops the same binary in at /etc/fs/zfs/mount and /usr/lib/fs/zfs/mount,
# which is how mount(8) and the mountall path reach ZFS -- `mount -F zfs`
# execs the helper for the filesystem type. `zfs mount` works without them;
# `mount -F zfs` and boot-time mounting of a non-legacy dataset do not. Adding
# them means deciding where /etc/fs lives in this image, which is the image
# builder's business.
mkDerivation {
  pname = "zfs";
  path = "usr/src/cmd/zfs";

  # $(MACH64) indexes the library search path Makefile.master builds into
  # $(LDLIBS64); see mkDerivation.nix's `machMakeFlags`.
  illumosMach = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    # The whole point of the conversion; see the header comment.
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # zfs_prop.h / zfs_deleg.h, the property and delegation tables shared with
    # the kernel; the code behind them is already inside libzfs.
    "usr/src/common/zfs"

    # <sys/fs/zfs.h> and <sys/zfs_project.h>.
    "usr/src/uts/common/fs/zfs"

    # `INCS += -I../../lib/libzutil/common`.
    "usr/src/lib/libzutil/common"

    # <directory.h> -- libidmap's directory-service interface, which
    # `zfs allow` uses to turn a name into a SID. libidmap's `dev` output does
    # not carry it (its own Makefile installs it, and we build the amd64
    # subdirectory directly), so take it from the tree.
    "usr/src/lib/libidmap/common"
  ];

  extraNativeBuildInputs = [
    # illumos' compiler wrapper; the gate makefiles invoke $(CC) as `cw`.
    cw
    ctfconvert
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

  # `CPPFLAGS.first` rather than `CPPFLAGS` so that Makefile.master's own -D
  # flags and the Makefile's own $(INCS) survive, and through `makeFlagsArray`
  # because the value contains a space, which a `makeFlags` entry would be
  # word-split on.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I\$(SRC)/lib/libidmap/common")
  '';

  makeFlags = [
    # One `ctfconvert` over the linked binary; see zpool.nix.
    "CTF_MODE=link"

    # The other half of $(POST_PROCESS) is `$(STRIP) -x $@`, illumos strip(1)
    # syntax that GNU strip rejects.
    "STRIP_STABS=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all` rather than the default `install`, which also wants to write the
  # /usr/sbin, /usr/lib/fs/zfs and /etc/fs/zfs links described above.
  buildFlags = [ "all" ];
  dontInstall = false;

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

  # The point of the conversion, checked rather than asserted: a hand-compiled
  # binary cannot have a CTF container, so the section's presence is proof that
  # the component makefile really drove this build.
  #
  # `postFixup` rather than `installCheckPhase`: nixpkgs turns
  # `doInstallCheck` off whenever the build platform cannot execute the host
  # platform's binaries, so under cross -- which is the only way this package is
  # ever built -- an installCheck silently never runs at all. Doing it here also
  # puts the check *after* fixup's strip, which is the part worth checking:
  # .SUNW_ctf is a non-allocated PROGBITS section that `strip -S` leaves alone,
  # but that is an observation about GNU strip rather than a guarantee.
  postFixup = ''
    ctfProg="$out/bin/zfs"
    if [ ! -f "$ctfProg" ]; then
      echo "zfs is not where the CTF check expects it ($ctfProg)" >&2
      exit 1
    fi
    if ! $READELF -S "$ctfProg" | grep -q '[.]SUNW_ctf'; then
      echo "no .SUNW_ctf section in zfs: the CTF step did not run" >&2
      $READELF -S "$ctfProg" >&2
      exit 1
    fi
    echo "zfs carries a .SUNW_ctf section"
  '';

  meta = {
    description = "illumos ZFS dataset administration tool";
    mainProgram = "zfs";
  };
}
