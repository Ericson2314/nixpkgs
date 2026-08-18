{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
  libnsl,
  # libnsl.so.1 pulls in libmp/libmd, and the illumos link-editor insists on
  # finding a shared object's own dependencies on the link path.
  libmd,
  libmp,
}:

# libsocket.so.1 -- the public BSD sockets API. `libc.so.1` exports only the
# private syscall wrappers (`_so_socket`, `_so_connect`, `_so_accept`,
# `_so_bind`, `_so_getpeername`, ...); `socket`, `connect`, `bind`, `listen`,
# `accept`, `setsockopt`, `getaddrinfo`, `getnameinfo`, `getservbyname`,
# `getifaddrs`, `rcmd`, `rexec` and the rest all live here.
#
# That is why `-lsocket` was unresolvable: it is not folded into libc on
# illumos, unlike glibc. `openssl` gets all the way through libcrypto and
# libssl before dying on `cannot find -lsocket`, and `tcl` (hence `sqlite`)
# silently falls back to `compat/fake-rfc2553.c` because its configure test for
# `getaddrinfo` cannot link.
#
# `Makefile.com` links against `-lnsl -lc`: the socket layer reaches into
# libnsl for netdir/netconfig transport lookup and for the RPC used by
# `bootparams_getbyname` and `netmasks`.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libsocket/amd64";
  pname = "libsocket-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsocket"

    # Makefile.com's `-I../../common/inc` is dead -- resolved from the amd64
    # build directory it names `usr/src/lib/common/inc`, which does not exist
    # in the gate -- so there is nothing to add for it here.

    "usr/src/common/mapfiles"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly. `libmd`/`libmp` appear only because they are libnsl's own
  # `DT_NEEDED`s and the illumos link-editor insists on finding a dependency's
  # dependencies on the link path.
  #
  # <libsocket_priv.h> is installed into /usr/include by the *top*
  # lib/libsocket/Makefile (HDRS, line 27). We build amd64 directly, so point
  # at the source directory instead. It rides on CPPFLAGS.first rather than
  # CPPFLAGS because a command-line CPPFLAGS would discard Makefile.com's own
  # -DSYSV -D_REENTRANT.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libsocket/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) \$(PICS) \$(EXTPICS) -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "LD=${buildPackages.writeShellScript "illumos-ld" ''
      unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
      exec ${buildPackages.illumos.ld}/bin/ld "$@"
    ''}"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libsocket.so.1 "$out/lib/"
    ln -s libsocket.so.1 "$out/lib/libsocket.so"

    runHook postInstall
  '';
}
