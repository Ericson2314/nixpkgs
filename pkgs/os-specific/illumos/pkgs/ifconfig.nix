{
  mkDerivation,

  cw,

  libdhcpagent,
  libdlpi,
  libinetutil,
  libipmp,
  libdladm,
  libipadm,
  libxnet,
  libsocket,
  libnsl,
  # Included-from dependencies rather than linked ones: <libdladm.h> pulls in
  # <libnvpair.h> and <kstat.h>, and <dhcpagent_ipc.h> pulls in
  # <dhcp_inittab.h> out of libdhcputil.
  libnvpair,
  libkstat,
  libdhcputil,
}:

# ifconfig(8) -- usr/src/cmd/cmd-inet/usr.sbin/ifconfig.
#
# This is the immediate goal of the whole libdladm/libipadm branch: it is how
# an address gets onto the virtio NIC in the illumos VM, and therefore the
# last thing between a booted guest and a reachable sshd.
#
# Modern illumos ifconfig is mostly a command-line parser in front of
# libipadm: `ifconfig net0 plumb` is `ipadm_create_if`, `ifconfig net0
# 10.0.2.15/24 up` is `ipadm_create_addr` with a volatile (IPADM_OPT_ACTIVE)
# request. That matters here because the persistent half of libipadm needs
# ipmgmtd, which is not packaged -- see libipadm.nix -- while the volatile
# half goes straight to the kernel through ioctls on /dev/udp. The static
# address assignment this exists for is entirely in the volatile half.
#
# `revarp.c` (RARP-based address discovery at boot) and the DHCP subcommands
# are built too and are why `-ldhcpagent` is on the link line; neither is
# reachable in this VM without the corresponding daemon.
mkDerivation {
  pname = "ifconfig";
  path = "usr/src/cmd/cmd-inet/usr.sbin/ifconfig";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `compat.o` is `COMMONOBJS`: it is compiled straight into the program out
    # of the shared cmd-inet directory rather than linked from a library, so
    # its source has to be present, along with the fragment that defines
    # `CMDINETCOMMONDIR` and the pattern rule that builds it.
    "usr/src/cmd/cmd-inet/Makefile.cmd-inet"
    "usr/src/cmd/cmd-inet/common"

    # The Makefile puts `-I$(SRC)/common/net/dhcp` on CPPFLAGS: ifconfig
    # includes <netinet/dhcp.h> from there for the DHCP subcommands.
    "usr/src/common/net/dhcp"

    # `ifconfig.c` includes <libsocket_priv.h>, which reaches upstream builds
    # only through the proto area -- lib/libsocket's top Makefile installs it
    # into /usr/include -- so take it from the source directory, exactly as
    # getent.nix and libinetutil.nix already do.
    "usr/src/lib/libsocket/common"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    libdhcpagent
    libdlpi
    libinetutil
    libipmp
    libdladm
    libipadm
    libxnet
    libsocket
    libnsl
    libnvpair
    libkstat
    libdhcputil
  ];

  # `CPPFLAGS.first` rather than `CPPFLAGS` so that Makefile.master's own -D
  # flags and the Makefile's own -I flags survive, and through `makeFlagsArray`
  # rather than `makeFlags` because the value contains spaces, which
  # `makeFlags` entries would be word-split on.
  #
  # Only the source directory is named here; the library headers arrive as
  # `-isystem` from buildInputs, which is early enough for a command (unlike
  # the library packages, where a private regex.h makes the order matter --
  # see mkDerivation.nix).
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I\$(SRC)/lib/libsocket/common")
  '';

  makeFlags = [
    # illumos' MACH/MACH64 are not uname processor strings; on x86 they are
    # "i386" and "amd64".
    "MACH=i386"
    "MACH64=amd64"

    # cmd-inet/usr.sbin/ifconfig has no amd64 subdirectory, so upstream builds
    # it 32-bit. This port is 64-bit only -- there is no 32-bit libc packaged
    # -- so the macros Makefile.cmd.64 would have set are passed here instead.
    # See getent.nix, which does the same for the same reason.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # ifconfig sets `ROOTFS_PROG`, not `PROG`, so Makefile.cmd:485 is live:
    #
    #   64ONLY = $($(MACH)_64ONLY)
    #   $(64ONLY)$(ROOTFS_PROG) := LDFLAGS += -Wl,-I/lib/ld.so.1
    #
    # `i386_64ONLY` is undefined, so on x86 that pins the *32-bit* interpreter
    # onto a program this port builds 64-bit, naming a file that does not
    # exist. The kernel then cannot map it and kills the process outright --
    # "ifconfig: Cannot find /lib/ld.so.1", exit 137, no other output, which
    # reads like a crash rather than a link-time mistake. Setting the guard to
    # the comment character disables the line and leaves the wrapper's own
    # absolute store-path interpreter in place. See mount-ufs.nix, which hit
    # exactly this.
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

  # `all` rather than the default `install`: upstream's install target wants
  # to write $(ROOTSBINPROG) and then drop a ../../sbin relative symlink into
  # $(ROOTUSRSBIN), which is more of upstream's layout than is useful here.
  buildFlags = [ "all" ];
  dontInstall = false;

  # Installed into $out/sbin rather than $out/bin to match upstream's
  # placement: ifconfig is a root-filesystem program, and the libraries it
  # links (libdladm, libipadm, libdlpi, ...) all include Makefile.rootfs for
  # the same reason.
  installPhase =
    ''
      runHook preInstall

    ''
    # `mkdir`/`cp` rather than `install -D`: the `install` on PATH here is
    # illumos' own (mkDerivation puts it there), and it does not take -D.
    + ''
      mkdir -p $out/sbin
      cp ifconfig $out/sbin/ifconfig
      chmod 755 $out/sbin/ifconfig

      runHook postInstall
    '';

  meta = {
    description = "illumos ifconfig(8)";
    mainProgram = "ifconfig";
  };
}
