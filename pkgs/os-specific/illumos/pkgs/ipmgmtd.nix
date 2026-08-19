{
  lib,
  mkDerivation,

  cw,
  headers,

  libipadm,
  libdladm,
  libkstat,
  libnvpair,
  libsecdb,
  libnsl,
  libumem,
  libscf,
}:

# ipmgmtd(8) -- the IP management daemon, usr/src/cmd/cmd-inet/lib/ipmgmtd.
#
# The exact counterpart of dlmgmtd, one layer up the stack, and missing for the
# same reason: libipadm does not talk to the kernel about addresses, it asks
# this daemon over a door at a hard-coded path,
#
#     #define IPMGMT_DOOR "/etc/svc/volatile/ipadm/ipmgmt_door"
#     (lib/libipadm/common/ipadm_ipmgmt.h:113)
#
# opened on demand in `ipadm_door_call()` (lib/libipadm/common/libipadm.c:918).
# With no daemon the open fails and every caller gets that errno back, which
# ifconfig prints as
#
#     ifconfig: could not create address:Object not found
#
# There is no way around it from ifconfig's side. Every spelling of an address
# -- `ifconfig vioif0 10.0.2.15/24`, the classic `inet ... netmask ...` form,
# and `set` -- converges on `ipadm_create_addr()` (ifconfig.c:761, :835), so
# there is no legacy ioctl path still reachable in the shipped program.
#
# Note the ordering this implies for bring-up: dlmgmtd first, because
# `ifconfig <if> plumb` is a datalink lookup and fails without it; then this,
# because assigning the address is an ipadm operation. The two failures look
# nothing alike -- "Interface does not exist" against "Object not found" -- but
# both are a missing daemon rather than a missing device.
mkDerivation {
  pname = "ipmgmtd";
  path = "usr/src/cmd/cmd-inet/lib/ipmgmtd";

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

    # The makefile includes ../../../../lib/Makefile.lib before anything else,
    # for ROOTFS_LIBDIR -- it installs to /lib/inet rather than to a bin
    # directory. Nothing is installed from here, but the include still has to
    # resolve for the makefile to parse at all.
    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    headers
    libipadm
    libdladm
    libkstat
    libnvpair
    libsecdb
    libnsl
    libumem
    libscf
  ];

  makeFlags = [
    # 64-bit, as everything here is. cmd-inet/lib/ipmgmtd has no amd64
    # subdirectory, so upstream builds it 32-bit and we pass what
    # Makefile.cmd.64 would have set. See mount-ufs.nix for the full account.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # ipmgmtd installs under $(ROOTFS_LIBDIR), which makes it a $(ROOTFS_PROG)
    # and so subject to Makefile.cmd's 32-bit interpreter pin. Same trap, same
    # remedy as mount-ufs and dlmgmtd.
    "64ONLY=$(POUND_SIGN)"

    # This makefile splices CTFCONVERT_O and CTFMERGE into its own link rule
    # rather than using the usual $(POST_PROCESS) hooks -- it says so outright
    # ("Instrument ipmgmtd with CTF data to ease debugging") -- so both have to
    # be neutralised or the link shells out to target tools that do not run on
    # the build host.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"
    "CTFCONVERT_HOOK="
    "CTFMERGE_HOOK="
    "CTF_FLAGS="

    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all`, not `install`: the install target wants $(ROOTSVCNETWORK) for the
  # manifest and an $(ROOTETC)/ipadm owned by an `ipadm` user that does not
  # exist here. Placed by hand below, as in dlmgmtd.nix.
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall

  ''
  # /lib/inet is where upstream puts it, and the SMF method script below
  # names that path; keep the layout so the shipped script stays usable.
  + ''
    mkdir -p $out/lib/inet
    cp ipmgmtd $out/lib/inet/ipmgmtd
    chmod 755 $out/lib/inet/ipmgmtd

  ''
  # The SMF manifest and its method script, for a configuration that runs
  # this under SMF rather than by hand.
  + ''
    mkdir -p $out/lib/svc/manifest/network $out/lib/svc/method
    cp network-ipmgmt.xml $out/lib/svc/manifest/network/ipmgmt.xml
    cp net-ipmgmt $out/lib/svc/method/net-ipmgmt
    chmod 755 $out/lib/svc/method/net-ipmgmt

  ''
  # The seed address database. Like dlmgmtd's datalink.conf this is rewritten
  # in place as addresses come and go, so a consumer has to copy it to
  # writable storage rather than symlink it out of the store.
  + ''
    mkdir -p $out/share/ipmgmtd
    cp ipadm.conf $out/share/ipmgmtd/ipadm.conf

    runHook postInstall
  '';

  meta = {
    description = "illumos IP management daemon";
    mainProgram = "ipmgmtd";
  };
}
