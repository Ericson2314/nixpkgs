{
  lib,
  mkDerivation,

  cw,

  libsecdb,
}:

# getent(1) -- illumos' own, out of usr/src/cmd/getent.
#
# `unixtools.getent` needs a getent for every platform, and the fallbacks do
# not fit here: NetBSD's ships a `compat` <netconfig.h> whose `struct netconfig`
# and `getnetconfigent` prototype collide head-on with illumos' <sys/netconfig.h>
# (illumos has TI-RPC in the base system, NetBSD does not), so it does not even
# compile against these headers. The native one is a better answer anyway --
# it knows about the illumos-only tables (auth_attr, exec_attr, prof_attr,
# user_attr, netmasks, ethers) and about the name-service switch.
#
# Two things about the upstream build have to be adjusted:
#
#  * `cmd/getent` has no `amd64` subdirectory, so it is one of the many illumos
#    commands that upstream still builds 32-bit. This port is 64-bit only --
#    there is no 32-bit libc packaged -- so the macros that `Makefile.cmd.64`
#    would have set are passed on the command line instead. They are all plain
#    assignments (see `usr/src/Makefile.master.64`), so this is exactly
#    equivalent to including that fragment, without inventing an `amd64`
#    subdirectory upstream does not have.
#
#  * `-lproject` is dropped, and `dogetproject.c` replaced by a stub. See the
#    comment on `postPatch` below.
mkDerivation {
  pname = "getent";
  path = "usr/src/cmd/getent";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `dogetnetmask.c` includes <libsocket_priv.h> for `getnetmaskbyaddr`.
    # It is installed into /usr/include by the *top* lib/libsocket/Makefile
    # (HDRS, line 27), which the libsocket package does not run -- it builds
    # the amd64 subdirectory directly. Point at the source directory instead,
    # exactly as libsocket.nix does for its own build.
    "usr/src/lib/libsocket/common"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [ libsecdb ];

  # `getent project` is the one table that would drag in a large chunk of
  # userland: it calls `getprojent`/`getprojbyname` from libproject, and
  # libproject links `-lproc -lpool` -- libproc pulls in libctf, libelf and
  # librtld_db, libpool pulls in libscf, libxml2, libexacct and libnvpair.
  # That is a lot of tree to port for `/etc/project`, which is resource-control
  # configuration that a Nix-built illumos system does not populate at all.
  #
  # So: drop `-lproject` and replace `dogetproject.c` with a stub returning
  # EXC_ENUM_NOT_SUPPORTED, which is the same exit status upstream gives for a
  # table it cannot enumerate. `getent.c`'s dispatch table only needs the
  # symbol to exist, so nothing else in the command changes and every other
  # table behaves exactly as upstream.
  postPatch = ''
    substituteInPlace usr/src/cmd/getent/Makefile \
      --replace-fail 'LDLIBS	+= -lsecdb -lsocket -lnsl -lproject' \
                     'LDLIBS	+= -lsecdb -lsocket -lnsl'

    cat > usr/src/cmd/getent/dogetproject.c <<'EOF'
    /*
     * Stub replacing the libproject-backed implementation; see getent.nix.
     */

    #include "getent.h"

    /* ARGSUSED */
    int
    dogetproject(const char **list)
    {
    	return (EXC_ENUM_NOT_SUPPORTED);
    }
    EOF
  '';

  # Through `makeFlagsArray` rather than `makeFlags` because the value contains
  # a space, and `makeFlags` entries are word-split. `CPPFLAGS.first` rather
  # than `CPPFLAGS` so that Makefile.master's own -D flags survive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I\$(SRC)/lib/libsocket/common")
  '';

  makeFlags = [
    # The contents of usr/src/Makefile.master.64, restricted to the macros a
    # command build actually reads. `LDLIBS.cmd` rather than `LDLIBS`, because
    # the package Makefile appends its own libraries to `LDLIBS` and a
    # command-line macro would silently discard them.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # `$(POST_PROCESS)` ends in strip/CTF steps that need illumos target tools
    # on the build host. Nothing here consumes CTF for a command.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # The link goes through the compiler driver, which reaches GNU ld, and
    # every option in these two macros is Solaris link-editor syntax that GNU
    # ld rejects outright:
    #
    #   LDFLAGS.cmd = $(BDIRECT) ... $(MAPFILE.NES:%=-Wl,-M%) ...
    #   LDCHECKS    = -Wl,-zassert-deflib -Wl,-zguidance -Wl,-zfatal-warnings
    #
    # Nothing here is load-bearing for a command: -Bdirect is a binding
    # optimisation, the -zguidance/-zassert-deflib checks are build hygiene,
    # and the three mapfiles (map.noexstk, map.pagealign, map.noexdata) ask
    # for a non-executable stack and data segment, which GNU ld gives by
    # default on amd64. vtfontcvt.nix already clears LDCHECKS for the same
    # reason.
    #
    # Note that this differs from the *library* packages, which do link
    # through illumos' own ld (see mkDerivation.nix's `illumosLd`): they have
    # versioning mapfiles that genuinely need it. A command has none.
    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `$(ROOTPROG)` is `$(ROOTBIN)/getent`, and the setup hook has already
  # rewritten `$(ROOT)/usr/bin` to `$(BINDIR)`; the directory still has to
  # exist before `$(INS.file)` runs.
  preInstall = ''
    mkdir -p $out/bin
  '';

  meta.mainProgram = "getent";
}
