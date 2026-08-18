{
  lib,
  mkDerivation,

  cw,
  headers,

  libdladm,
  libkstat,
  librcm,
  libdlpi,
  libavl,
  libnvpair,
  libsysevent,
  libcontract,
}:

# dlmgmtd(8) -- the datalink management daemon, usr/src/cmd/dlmgmtd.
#
# Nothing that configures a network interface works without it. libdladm does
# not read datalink state from the kernel directly; it asks this daemon over a
# door, opened on demand in `dladm_door_fd()` (lib/libdladm/common/libdladm.c).
# With no daemon there is no door, so every libdladm consumer -- including
# ifconfig, which reaches it through libipadm -- fails before it does anything:
#
#     ifconfig: unable to open handle to libipadm: Datalink does not exist
#
# and it fails for `ifconfig -a` as much as for `ifconfig vioif0 plumb`, so it
# reads as "there is no NIC" rather than "there is no daemon".
#
# This is the layer above soconfig. With the socket-to-transport mappings
# loaded but no dlmgmtd, `socket(AF_INET, ...)` succeeds and datalink lookup is
# what fails instead; the two have to be brought up in that order.
#
# Upstream runs it as svc:/network/datalink-management, whose method script
# (svc-dlmgmtd) is shipped here too so that an SMF-based configuration can use
# it unmodified.
mkDerivation {
  pname = "dlmgmtd";
  path = "usr/src/cmd/dlmgmtd";

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
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    headers
    libdladm
    libkstat
    librcm
    libdlpi
    libavl
    libnvpair
    libsysevent
    libcontract
  ];

  makeFlags = [
    # 64-bit, as everything here is; cmd/dlmgmtd has no amd64 subdirectory so
    # upstream builds it 32-bit and we pass what Makefile.cmd.64 would have
    # set. See mount-ufs.nix for the full account.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # dlmgmtd installs via $(ROOTSBINPROG), which makes it a $(ROOTFS_PROG) and
    # so subject to Makefile.cmd's 32-bit interpreter pin. Same trap, same
    # remedy as mount-ufs.
    "64ONLY=$(POUND_SIGN)"

    # The CTF hooks here are not the usual $(POST_PROCESS) ones -- this
    # makefile splices CTFCONVERT_O and CTFMERGE into its own link rule -- so
    # both have to be neutralised or the link shells out to target tools that
    # do not run on the build host.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"
    "CTFCONVERT_HOOK="
    "CTFMERGE_HOOK="
    "CTF_FLAGS="

    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all`, not `install`: the install target wants $(ROOTSVCNETWORK) for the
  # manifest and $(ROOTETC)/dladm for the seed config, which is more of
  # upstream's layout than belongs in a store path. Placed by hand below.
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/sbin
    cp dlmgmtd $out/sbin/dlmgmtd
    chmod 755 $out/sbin/dlmgmtd

  ''
  # The SMF manifest and its method script, for a configuration that runs
  # this under SMF rather than by hand.
  + ''
    mkdir -p $out/lib/svc/manifest/network $out/lib/svc/method
    cp dlmgmt.xml $out/lib/svc/manifest/network/dlmgmt.xml
    cp svc-dlmgmtd $out/lib/svc/method/svc-dlmgmtd
    chmod 755 $out/lib/svc/method/svc-dlmgmtd

  ''
  # The seed datalink database. dlmgmtd expects /etc/dladm/datalink.conf to
  # exist and to be writable; a consumer has to copy this to writable
  # storage rather than symlink it into the store.
  + ''
    mkdir -p $out/share/dlmgmtd
    cp datalink.conf $out/share/dlmgmtd/datalink.conf

    runHook postInstall
  '';

  meta = {
    description = "illumos datalink management daemon";
    mainProgram = "dlmgmtd";
  };
}
