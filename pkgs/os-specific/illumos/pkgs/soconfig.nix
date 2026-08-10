{
  mkDerivation,

  cw,
}:

# soconfig(8) -- out of usr/src/cmd/cmd-inet/usr.sbin.
#
# This is the piece that makes `socket(2)` work at all. sockfs keeps *no*
# built-in family/type/protocol table: `sockparams_init()`
# (uts/common/fs/sockfs/sockparams.c:87) creates an empty list, and
# `solookup()` (:663) walks that list and returns EAFNOSUPPORT when it is
# empty. The list is populated only by the `sockconfig` system call, and
# soconfig(8) is the only thing that issues it -- so on a system where
# soconfig has never run, *every* socket() call fails, unix-domain included.
#
# The table itself is data, not code: cmd/cmd-inet/etc/sock2path.d/. See the
# nixbsd boot image for the copy that is actually loaded, which differs from
# upstream's in naming devices by their /devices path (there is no devfsadm
# here to populate /dev).
#
# Built as a single target rather than by running the directory's `all`:
# usr.sbin/Makefile builds some forty programs, between them wanting
# libdhcpagent, libdladm, libipadm, libipmp, libdlpi, libtsnet, libbsm, libpam,
# librpcsvc and mech_krb5, none of which are packaged. soconfig itself is in
# neither $(SOCKETPROG) nor $(NSLPROG) -- it links libc and nothing else, since
# `_sockconfig()` is a libc syscall stub (lib/libc/common/sys/_sockconfig.S).
mkDerivation {
  pname = "soconfig";
  path = "usr/src/cmd/cmd-inet/usr.sbin";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `include ../Makefile.cmd-inet` at usr.sbin/Makefile:84.
    "usr/src/cmd/cmd-inet/Makefile.cmd-inet"

    # usr.sbin/Makefile:101 has an unconditional
    # `include $(SRC)/lib/gss_mechs/mech_krb5/Makefile.mech_krb5`. Nothing
    # soconfig needs comes out of it, but the file has to exist for dmake to
    # parse the makefile at all.
    "usr/src/lib/gss_mechs/mech_krb5/Makefile.mech_krb5"
  ];

  extraNativeBuildInputs = [ cw ];

  # The single-suffix `%: %.c` rule in cmd/Makefile.targ.
  buildFlags = [ "soconfig" ];

  makeFlags = [
    # illumos' MACH/MACH64 are not uname processor strings; on x86 they are
    # "i386" and "amd64".
    "MACH=i386"
    "MACH64=amd64"

    # The contents of usr/src/Makefile.master.64 that a command build reads;
    # cmd/cmd-inet/usr.sbin has no amd64 subdirectory. See getent.nix, which
    # does exactly the same thing and explains why.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # CTF and strip steps need illumos target tools on the build host.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `install` here would build every other program in the directory, so do the
  # one copy by hand. Upstream puts soconfig in $(ROOTSBIN) (it is in
  # $(ROOTFS_PROG)) -- i.e. /sbin, not /usr/sbin -- because it runs before
  # /usr is mounted.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cp soconfig "$out/bin/soconfig"
    runHook postInstall
  '';

  meta.mainProgram = "soconfig";
}
