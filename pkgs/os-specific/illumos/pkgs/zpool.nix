{
  mkDerivation,

  cw,
  ctfconvert,

  headers,

  libzfs,
  libzfs_core,
  libzutil,
  libnvpair,
  libdevid,
  libefi,
  libdiskmgt,
  libuutil,
  libumem,
  libm,
  libcmdutils,
  # <kstat.h>, included by cmd/stat/common/statcommon.h. zpool needs no kstat
  # call itself; the header comes with the shared timestamp code.
  libkstat,
  # `highbit64`/`lowbit64` -- see the note below on `-lzpool`.
  libfakekernel,
}:

# zpool(8) -- create, import, export, scrub and report on storage pools.
#
# Driven through usr/src/cmd/zpool/Makefile rather than compiled by hand. The
# reason to care is CTF: that Makefile includes ../Makefile.ctf, and CTF is
# arranged entirely by the build system -- there is no compiler flag that
# produces it. A hand-rolled `$CC -o zpool *.c` cannot have it by construction,
# which is what the previous version of this file was and why `zpool` had none.
#
# `CTF_MODE=link` is Makefile.ctf's own documented alternative to its default
# (usr/src/cmd/Makefile.ctf:27-31): one `ctfconvert` over the linked binary
# instead of a per-object convert plus a merge. Both are upstream; `link` is
# chosen here because it needs only `ctfconvert` on the build host, and because
# the default `objs` mode's expansion of $(POST_PROCESS) is
#
#     : $@ ;  ; ctfmerge ... ; $(STRIP_STABS) ;
#
# -- `POST_objs` (Makefile.ctf:33) begins with its own `;`, and Makefile.master
# :1000 supplies a second one -- which is a shell syntax error anywhere the
# gate's own dmake is not the thing reading it.
#
# `-lzpool` is deliberately absent from the link, and this is the one real
# departure from upstream's Makefile. libzpool is the *userland build of the
# ZFS core* -- the whole of uts/common/fs/zfs compiled against libfakekernel --
# and it exists for zdb(8) and ztest, which run the DMU in a process. zpool
# does not call into it: every operation it performs goes through libzfs to
# /dev/zfs. The link succeeds without it, which is the check that matters;
# `-lfakekernel` supplies the two bit-twiddling helpers (`highbit64`,
# `lowbit64`) that zpool_vdev.c does take from that side of the tree.
#
# The reason libzpool cannot simply be built here is that its Makefile
# generates ../common/zfs.h with `dtrace -h` and compiles a DTrace provider
# object into EXTPICS, and dtrace(8) is not packaged. Rather than stub that
# out, note it and link what is actually used. If a future zpool subcommand
# does need libzpool, the link will say so rather than the program failing at
# run time -- an unresolved symbol is a build error.
mkDerivation {
  pname = "zpool";
  path = "usr/src/cmd/zpool";

  # Its makefile chain indexes library directories by $(MACH64) (Makefile
  # .master's `LDLIBS64 = $(ENVLDLIBS1:%=%/$(MACH64)) ...`), so it needs the
  # illumos spelling of the CPU. See `machMakeFlags` in mkDerivation.nix.
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

    # $(MAPFILE.NES), $(MAPFILE.PGA) and $(MAPFILE.NED) -- the non-executable
    # stack/data and page-alignment mapfiles Makefile.cmd puts on every command
    # through $(LDFLAGS.cmd). GNU ld read -M as "write a link map" and never
    # opened them; illumos ld does, and stops if they are not there.
    "usr/src/common/mapfiles"

    # `statcommon.h`/`timestamp.c`, which cmd/stat/Makefile.stat adds to
    # $(OBJS): `zpool iostat -T d` prints a timestamp between samples, and the
    # formatting is shared with vmstat(8), iostat(8) and the rest of that
    # family. The Makefile *include*s that fragment, so it has to be here too,
    # not just the sources it names.
    "usr/src/cmd/stat/Makefile.stat"
    "usr/src/cmd/stat/common"

    # zfs_comutil.c / zfeature_common.c / zfs_prop.h, the property and feature
    # tables shared with the kernel. zpool includes the headers; the code is
    # already inside libzfs.
    "usr/src/common/zfs"

    # <sys/fs/zfs.h> and the private on-disk declarations.
    "usr/src/uts/common/fs/zfs"

    # `INCS += -I../../lib/libzutil/common` -- <libzutil.h>'s private
    # companions, which libzutil's `dev` output does not carry.
    "usr/src/lib/libzutil/common"
  ];

  # ctfconvert runs on the build host and reads the illumos objects this
  # produces; splicing hands out the build-platform instance. Only ctfconvert,
  # not ctfmerge, because of `CTF_MODE=link` above.
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
    libnvpair
    libdevid
    libefi
    libdiskmgt
    libuutil
    libumem
    libm
    libcmdutils
    libkstat
    libfakekernel
  ];

  # `LDLIBS` in full rather than `LDLIBS.cmd`, which is what a command
  # normally overrides (see getent.nix): the Makefile appends `-lzpool` to
  # `LDLIBS` itself, and dropping that one library is the whole reason this
  # cannot use the lighter-touch macro. Everything else in the value is
  # upstream's list, plus `$(LDLIBS64)`/`$(LDSTACKPROTECT)`, which is what
  # Makefile.cmd:118 and Makefile.master.64 would otherwise have put there.
  #
  # Through `makeFlagsArray` because the value contains spaces, which a
  # `makeFlags` entry would be word-split on; `\$` keeps the shell from
  # expanding what is a make macro reference.
  preBuild = ''
    makeFlagsArray+=(
      "LDLIBS=\$(LDLIBS64) \$(LDSTACKPROTECT) -lzfs -lnvpair -ldevid -lefi -ldiskmgt -luutil -lumem -lzutil -lm -lfakekernel"
    )
  '';

  makeFlags = [
    # One `ctfconvert` over the linked binary. See the header comment.
    "CTF_MODE=link"

    # `STRIP_STABS` is the other half of $(POST_PROCESS): `$(STRIP) -x $@`,
    # which is illumos strip(1) syntax that GNU strip rejects. nixpkgs' own
    # fixup phase strips these binaries anyway, and it is careful to leave
    # .SUNW_ctf alone -- which is the section this package exists to produce.
    "STRIP_STABS=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix for why
    # none of it is load-bearing for a command.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all` rather than the default `install`: upstream's install target writes
  # $(ROOTSBINPROG) and then drops ../../sbin relative symlinks into
  # $(ROOTUSRSBIN), which is more of upstream's layout than is useful here.
  buildFlags = [ "all" ];
  dontInstall = false;

  # /usr/sbin/zpool is a symlink to ../../sbin/zpool on a real system, because
  # importing the root pool has to work before /usr is mounted. Ship it in
  # `sbin` only; nothing here has a split /usr.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/sbin"
    cp zpool "$out/sbin/zpool"
    chmod 755 "$out/sbin/zpool"

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
    ctfProg="$out/bin/zpool"
    if [ ! -f "$ctfProg" ]; then
      echo "zpool is not where the CTF check expects it ($ctfProg)" >&2
      exit 1
    fi
    if ! $READELF -S "$ctfProg" | grep -q '[.]SUNW_ctf'; then
      echo "no .SUNW_ctf section in zpool: the CTF step did not run" >&2
      $READELF -S "$ctfProg" >&2
      exit 1
    fi
    echo "zpool carries a .SUNW_ctf section"
  '';

  meta = {
    description = "illumos ZFS storage pool configuration tool";
    mainProgram = "zpool";
  };
}
