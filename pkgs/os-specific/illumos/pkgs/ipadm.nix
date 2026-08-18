{
  mkDerivation,

  cw,
  ctfconvert,
  ctfmerge,

  headers,

  libipadm,
  libofmt,
  libinetutil,
  libnvpair,
  libipmp,
  libcmdutils,
  libxnet,
  libsocket,
  libnsl,
  libdladm,
  libkstat,
  libdlpi,
}:

# ipadm(8) -- the modern illumos interface for IP configuration.
#
# `ifconfig` still exists and still works, but it is the legacy tool: on
# illumos, persistent configuration, address objects and interface properties
# all live in ipadm, and svc:/network/physical drives ipadm rather than
# ifconfig.
#
# Packaged here for a second and more immediate reason: `ifconfig` cannot parse
# an address on this system. `in_getaddr()` (cmd-inet/usr.sbin/ifconfig) has no
# numeric fast path at all -- it goes straight to
#
#     getipnodebyname(str, AF_INET, 0, &error_num)
#
# so a literal dotted quad is resolved through the name service switch, and
# something in the `hosts`/`ipnodes` path is not working here even though the
# same nss_files.so.1 serves `passwd` correctly (`getent passwd root` works;
# `getent hosts localhost` returns nothing). The result is:
#
#     ifconfig: 10.0.2.15: bad address
#
# for every form -- plain, CIDR, and hex netmask alike.
#
# ipadm goes through `getaddrinfo()` (lib/libipadm/common/ipadm_addr.c:1895),
# which parses a numeric address with inet_pton before consulting any backend,
# so it is not affected by that. Which of the two is "right" is a separate
# question -- the hosts lookup should work and is worth fixing -- but this is
# the tool the system is supposed to be configured with regardless.
#
#     ipadm create-addr -T static -a 10.0.2.15/24 vioif0/v4
#
# Driven through cmd-inet/usr.sbin/ipadm/Makefile rather than compiled by hand.
# That makefile is not the shared cmd-inet/usr.sbin one that soconfig has to
# avoid -- ipadm has a directory of its own -- and it goes out of its way to
# produce CTF:
#
#     # Instrument ipadm with CTF data to ease debugging.
#     CTFCONVERT_HOOK = && $(CTFCONVERT_O)
#     CTFMERGE_HOOK = && $(CTFMERGE) -L VERSION -o $@ $(OBJS)
#
# (usr/src/cmd/cmd-inet/usr.sbin/ipadm/Makefile:70-73). Those hooks are spliced
# into Makefile.master's own `.c.o` rule (Makefile.master:1027) and into this
# Makefile's link rule, so they are exactly what a hand-rolled `$CC -o ipadm
# ipadm.c` threw away. Hence the per-object convert and the merge here, rather
# than zpool's and zfs's single `CTF_MODE=link` pass.
mkDerivation {
  pname = "ipadm";
  path = "usr/src/cmd/cmd-inet/usr.sbin/ipadm";

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
    "usr/src/cmd/Makefile.targ"

    # `include ../../Makefile.cmd-inet`, which defines $(CMDINETCOMMONDIR) --
    # on $(CPPFLAGS) here -- and the pattern rule for $(COMMONOBJS). ipadm's
    # $(COMMONOBJS) is empty, but the include and the -I are unconditional.
    "usr/src/cmd/cmd-inet/Makefile.cmd-inet"
    "usr/src/cmd/cmd-inet/common"
  ];

  extraNativeBuildInputs = [
    # illumos' compiler wrapper; the gate makefiles invoke $(CC) as `cw`.
    cw
    # Both, unlike zpool/zfs: this Makefile's own hooks convert each object and
    # then merge, which is upstream's default CTF shape. They run on the build
    # host over illumos objects, and splicing hands out that instance.
    ctfconvert
    ctfmerge
  ];

  buildInputs = [
    headers
    libipadm
    libofmt
    libinetutil
    libnvpair
    libipmp
    libcmdutils
    libxnet
    libsocket
    libnsl
    libdladm
    libkstat
    libdlpi
  ];

  makeFlags = [
    # cmd-inet/usr.sbin/ipadm has no amd64 subdirectory and does not include
    # Makefile.cmd.64, so upstream builds it 32-bit. This port is 64-bit only
    # -- there is no 32-bit libc packaged -- so the macros Makefile.cmd.64
    # would have set are passed here instead. See getent.nix and ifconfig.nix,
    # which do the same for the same reason.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # The DWARF that ctfconvert reads. The Makefile asks for it with a
    # target-conditional `$(OBJS) := CFLAGS += $(CTF_FLAGS)`, and the
    # command-line `CFLAGS` above outranks that, so '-g' has to be put back by
    # another route. This is the gate's own knob for it: Makefile.master:549
    # is `$(SRCDBGBLD)CSOURCEDEBUGFLAGS = $(CCGDEBUG)`, and CSOURCEDEBUGFLAGS is
    # already a term of both CFLAGS and CFLAGS64 (Makefile.master:552-559), so
    # setting it needs no guess about where in the flag order -g belongs.
    "CSOURCEDEBUGFLAGS=$(CCGDEBUG)"

    # ipadm sets `ROOTFS_PROG`, so Makefile.cmd:485 is live:
    #
    #   64ONLY = $($(MACH)_64ONLY)
    #   $(64ONLY)$(ROOTFS_PROG) := LDFLAGS += -Wl,-I/lib/ld.so.1
    #
    # `i386_64ONLY` is undefined, so on x86 that pins the *32-bit* interpreter
    # onto a program this port builds 64-bit, naming a file that does not
    # exist. The kernel then cannot map it and kills the process outright, with
    # no output, which reads like a crash rather than a link-time mistake.
    # Setting the guard to the comment character disables the line. See
    # ifconfig.nix and mount-ufs.nix, which hit exactly this.
    "64ONLY=$(POUND_SIGN)"

    # $(POST_PROCESS)'s other half is `$(STRIP) -x $@`, illumos strip(1)
    # syntax that GNU strip rejects. The CTF here does not come through
    # $(PROCESS_CTF) -- this Makefile has its own hooks -- so nothing else in
    # that macro is wanted.
    "STRIP_STABS=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix for why
    # none of it is load-bearing for a command.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all` rather than the default `install`, which also wants to write
  # $(ROOTCFGDIR)/ipadm.conf and a ../../sbin symlink under $(ROOTUSRSBIN).
  buildFlags = [ "all" ];
  dontInstall = false;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/sbin
    cp ipadm $out/sbin/ipadm
    chmod 755 $out/sbin/ipadm

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
    ctfProg="$out/bin/ipadm"
    if [ ! -f "$ctfProg" ]; then
      echo "ipadm is not where the CTF check expects it ($ctfProg)" >&2
      exit 1
    fi
    if ! $READELF -S "$ctfProg" | grep -q '[.]SUNW_ctf'; then
      echo "no .SUNW_ctf section in ipadm: the CTF hooks did not run" >&2
      $READELF -S "$ctfProg" >&2
      exit 1
    fi
    echo "ipadm carries a .SUNW_ctf section"
  '';

  meta = {
    description = "illumos IP administration tool";
    mainProgram = "ipadm";
  };
}
