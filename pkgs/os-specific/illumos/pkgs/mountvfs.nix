{
  lib,
  mkDerivation,

  headers,
}:

# mountvfs(1) -- mount(2) with an explicit filesystem type.
#
# Not an illumos program: a few dozen lines written here, for the same reason
# as `setaddr`, `klog` and `ditree`.
#
# illumos' mount(8) is a dispatcher. It parses the command line and then execs
# /usr/lib/fs/<fstype>/mount, which is where the real work happens. We package
# the NFS helper (`mount-nfs`, installed at that path) but not the dispatcher
# itself -- and virtio-fs has no helper anywhere, since upstream illumos has
# never had that filesystem.
#
# So a filesystem can be complete and working in the kernel and still be
# unmountable, because nothing in userland can make the call. That is not a
# hypothetical: the first virtio-fs boot got as far as
#
#     bash: mount: command not found
#
# with both modules built and staged and the qemu device attached, which tests
# nothing at all.
#
# mount(2) on its own is simple. The dispatcher exists for /etc/vfstab, mnttab
# bookkeeping and per-filesystem argument parsing -- none of which is needed to
# answer "does this filesystem mount".
#
# Retire this if a real mount(8) is ever packaged. Like `setaddr`, it is a
# bring-up crutch rather than a design.
mkDerivation {
  pname = "mountvfs";
  noLibc = false;

  # No illumos source subtree; the C is here. `path` still has to name
  # something in the gate for the shared mkDerivation plumbing.
  path = "usr/src/lib/libc";

  buildInputs = [
    headers
  ];

  dontConfigure = true;

  # No -l flags: mount(2) is in libc.
  buildPhase = ''
    runHook preBuild
    $CC -O2 -o mountvfs ${./mountvfs.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp mountvfs $out/bin/mountvfs
    chmod 755 $out/bin/mountvfs
    runHook postInstall
  '';

  meta = {
    description = "mount(2) with an explicit fstype, for filesystems with no mount helper";
    mainProgram = "mountvfs";
  };
}
