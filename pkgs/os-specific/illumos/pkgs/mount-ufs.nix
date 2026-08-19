{
  lib,
  mkDerivation,

  cw,
  headers,
}:

# mount(8) for UFS -- usr/src/cmd/fs.d/ufs/mount, which upstream installs as
# /usr/lib/fs/ufs/mount and reaches through the generic /usr/sbin/mount
# dispatcher.
#
# The immediate reason this is needed is that a UFS root is not writable
# without it. ufs_mountroot() sets VFS_RDONLY for ROOT_INIT
# (uts/common/fs/ufs/ufs_vfsops.c), so illumos always mounts the root
# read-only and gets to a writable one via a second, ROOT_REMOUNT pass --
# `mount -o remount,rw /` -- which upstream drives from
# svc:/system/filesystem/root. Without that the root filesystem being UFS
# rather than hsfs buys nothing at run time.
#
# Only the fstype-specific program is built, not the generic dispatcher in
# usr/src/cmd/fs.d/mount.c. The dispatcher's whole job is to look at
# /etc/vfstab and exec /usr/lib/fs/<fstype>/mount, and a caller that already
# knows it wants UFS can invoke this directly. Packaging the dispatcher as
# well is worth doing when there is a second filesystem to dispatch to.
mkDerivation {
  pname = "mount-ufs";
  path = "usr/src/cmd/fs.d/ufs/mount";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # $(MAPFILE.NES), $(MAPFILE.PGA) and $(MAPFILE.NED) -- the non-executable
    # stack/data and page-alignment mapfiles Makefile.cmd puts on every command
    # through $(LDFLAGS.cmd). GNU ld read -M as "write a link map" and never
    # opened them; illumos ld does, and stops if they are not there.
    "usr/src/common/mapfiles"

    # The fstype build fragments, and fslib.c -- which is compiled straight
    # into the program rather than linked from a library (Makefile.mount's
    # COMMONOBJ), so its source has to be here.
    "usr/src/cmd/fs.d/Makefile.fstype"
    "usr/src/cmd/fs.d/Makefile.mount"
    "usr/src/cmd/fs.d/Makefile.mount.targ"
    "usr/src/cmd/fs.d/fslib.c"
    "usr/src/cmd/fs.d/fslib.h"
  ];

  extraNativeBuildInputs = [ cw ];

  # This links nothing but libc, so it has no library dependency to reach the
  # illumos headers through the way most commands do (getent gets them via
  # libsecdb). Ask for them directly.
  buildInputs = [ headers ];

  makeFlags = [
    # cmd/fs.d/ufs/mount has no amd64 subdirectory, so upstream builds it
    # 32-bit. This port is 64-bit only -- there is no 32-bit libc packaged --
    # so the macros Makefile.cmd.64 would have set are passed here instead.
    # See getent.nix, which does the same for the same reason.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # ...and one consequence of that which is not just a macro. Makefile.cmd
    # pins the *32-bit* interpreter on anything installed into the root
    # filesystem (line 485):
    #
    #   64ONLY = $($(MACH)_64ONLY)
    #   $(64ONLY)$(ROOTFS_PROG) := LDFLAGS += -Wl,-I/lib/ld.so.1
    #
    # `i386_64ONLY` is undefined, so on x86 that line is live. It is right for
    # upstream, where a $(ROOTFS_PROG) is 32-bit precisely so that it runs
    # before /usr is mounted, and /lib/ld.so.1 is the 32-bit linker. Here the
    # program is 64-bit, so it names an interpreter that does not exist: the
    # kernel cannot map it and kills the process outright --
    #
    #   mount: Cannot find /lib/ld.so.1
    #   Killed
    #
    # -- with no output and exit 137, which reads like a crash rather than a
    # link-time mistake. Setting the guard to the comment character disables
    # the line, leaving the wrapper's own (absolute, store-path) interpreter,
    # which is what every other command here already links against.
    #
    # `getent` needs none of this because it sets PROG rather than ROOTFS_PROG.
    "64ONLY=$(POUND_SIGN)"

    # `$(POST_PROCESS)` ends in strip/CTF steps needing illumos target tools on
    # the build host, and nothing consumes CTF for a command.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix for why
    # none of it is load-bearing for a command.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all` rather than the default `install`: the install targets want to write
  # to $(ROOTETC)/fs/ufs and $(ROOTLIB)/fs/ufs and to drop a relative symlink
  # between them, which is more of upstream's layout than is useful here.
  buildFlags = [ "all" ];
  dontInstall = false;

  installPhase = ''
    runHook preInstall

  ''
  # Upstream's path for the fstype-specific program, so that a generic
  # mount(8) would find it if one is packaged later.
  #
  # `mkdir`/`cp` rather than `install -D`: the `install` on PATH here is
  # illumos' own (mkDerivation puts it there), and it does not take -D.
  + ''
    mkdir -p $out/lib/fs/ufs
    cp mount $out/lib/fs/ufs/mount
    chmod 755 $out/lib/fs/ufs/mount

    runHook postInstall
  '';

  meta = {
    description = "illumos UFS mount(8), for /usr/lib/fs/ufs/mount";
  };
}
