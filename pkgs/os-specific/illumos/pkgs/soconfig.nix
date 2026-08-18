{
  lib,
  mkDerivation,

  headers,
}:

# soconfig(8) -- usr/src/cmd/cmd-inet/usr.sbin/soconfig.
#
# This is what makes `socket(3SOCKET)` work at all. sockfs does not know which
# transport provider serves a given (family, type, protocol) triple; that
# mapping is data, loaded into the kernel at boot by this program from
# /etc/sock2path.d. The core entries live in the file named `system/kernel`:
#
#     2   2   0    tcp        # AF_INET,  SOCK_STREAM
#     2   1   0    udp        # AF_INET,  SOCK_DGRAM
#     26  2   0    tcp        # AF_INET6, SOCK_STREAM
#     26  1   0    udp        # AF_INET6, SOCK_DGRAM
#
# Until they are loaded, every AF_INET socket fails at creation:
#
#     ifconfig: socket: Address family not supported by protocol family
#
# and it fails in `ifconfig -a`, before any interface is named -- so it looks
# like a driver or a NIC problem and is neither. The ip/tcp/udp modules can be
# attached and the interrupt path can be perfect and networking still will not
# work, because nothing has told sockfs where to send an AF_INET request.
#
# Upstream runs it from svc:/system/device/local (cmd/svc/milestone/
# devices-local), which invokes it after devfsadm precisely because some of
# the mappings name /dev entries devfsadm has just created:
#
#     /sbin/soconfig -d /etc/sock2path.d
#
# Anything bringing up networking without that SMF service has to run it by
# hand, in the same order: devfsadm first, then this.
mkDerivation {
  pname = "soconfig";
  path = "usr/src/cmd/cmd-inet/usr.sbin";

  extraPaths = [
    # Not built -- installed. See the installPhase.
    "usr/src/cmd/cmd-inet/etc/sock2path.d"
  ];

  # `_sockconfig`, the one non-standard thing this calls, is in libc
  # (lib/libc/port/mapfile-vers), so there is no library to reach the illumos
  # headers through. Ask for them directly.
  buildInputs = [ headers ];

  dontConfigure = true;

  # THE ONE PACKAGE HERE THAT STAYS HAND-BUILT, and the reason is in one line of
  # one makefile.
  #
  # soconfig has no directory of its own: it is built by the shared
  # usr/src/cmd/cmd-inet/usr.sbin/Makefile, one entry in that directory's
  # `ROOTFS_PROG= hostconfig route soconfig` (line 39). That Makefile's line 124
  # is
  #
  #     include $(SRC)/lib/gss_mechs/mech_krb5/Makefile.mech_krb5
  #
  # unconditionally, for rlogin/rsh/telnet/tftpd:
  #
  #     make: Fatal error in reader: Makefile, line 122: Read of include file
  #     `.../lib/gss_mechs/mech_krb5/Makefile.mech_krb5' failed
  #
  # Dragging krb5 in to build one 645-line program that links only libc is a
  # bad trade. Two consequences of not using the makefile are worth knowing:
  #
  #  * `soconfig` is one of that directory's `ROOTFS_PROG`s, so Makefile.cmd
  #    would have pinned the 32-bit interpreter on it
  #    (`$(64ONLY)$(ROOTFS_PROG) := LDFLAGS += -Wl,-I/lib/ld.so.1`), which for
  #    a 64-bit build names an interpreter that does not exist and gets the
  #    process killed with no output. mount-ufs works around that with
  #    `64ONLY=$(POUND_SIGN)`; here the problem simply does not arise.
  #  * No CTF -- but there is none to gain here either way. CTF for a command
  #    comes from `include $(SRC)/cmd/Makefile.ctf` or from explicit
  #    CTFCONVERT_HOOK/CTFMERGE_HOOK lines, the way cmd/zpool, cmd/zfs and
  #    cmd-inet/usr.sbin/ipadm have them and are driven through their makefiles
  #    for exactly that reason. cmd-inet/usr.sbin/Makefile has neither, so
  #    upstream ships a soconfig with no CTF too. Nothing is being given up.
  #  * No mapfile, which a command does not need.
  buildPhase = ''
    runHook preBuild
    $CC -O2 -o soconfig soconfig.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

  ''
  # Upstream installs it as /sbin/soconfig, which is the path
  # svc:/system/device/local invokes. Written to $out/sbin for that reason,
  # though nixpkgs' fixup phase then folds sbin into bin -- so consumers
  # here should use $out/bin/soconfig.
  + ''
    mkdir -p $out/sbin
    cp soconfig $out/sbin/soconfig
    chmod 755 $out/sbin/soconfig

  ''
  # The mappings themselves. They are plain data files whose names are
  # URL-encoded package FMRIs (`system%2Fkernel` is `system/kernel`), and
  # `soconfig -d` reads the whole directory, so ship them beside the program
  # rather than making every consumer go find them in the gate.
  #
  # Everything but the Makefile: soconfig treats each regular file in the
  # directory as a mapping table and would choke on it.
  + ''
    mkdir -p $out/etc/sock2path.d
    for f in ../etc/sock2path.d/*; do
      case "$(basename "$f")" in
        Makefile) continue ;;
      esac
      cp "$f" $out/etc/sock2path.d/
    done

    runHook postInstall
  '';

  meta = {
    description = "illumos soconfig(8), which loads the socket-to-transport mappings";
    mainProgram = "soconfig";
  };
}
