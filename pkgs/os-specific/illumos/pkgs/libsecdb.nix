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
  # libnsl.so.1's own DT_NEEDEDs; the illumos link-editor insists on finding a
  # shared object's dependencies on the link path.
  libmd,
  libmp,
}:

# libsecdb.so.1 -- the RBAC database access library: `getauthattr`,
# `getexecattr`, `getprofattr`, `getuserattr` and `chkauthattr`, i.e. the
# read side of /etc/security/{auth,exec,prof}_attr and /etc/user_attr.
#
# Six objects and a mapfile; it is here because `cmd/getent` links `-lsecdb`
# for its auth_attr/exec_attr/prof_attr/user_attr tables. The lookups
# themselves go through the name-service switch in libnsl, hence `-lnsl`.
#
# Deliberately *not* joined into the libc composite: unlike libsocket/libnsl,
# nothing outside illumos userland probes for `-lsecdb`.
mkDerivation {
  libcMinimal = true;
  path = "usr/src/lib/libsecdb/amd64";
  pname = "libsecdb";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsecdb"

    # `common/getexecattr.c` includes <getxby_door.h>, the nscd door protocol.
    # It is not a public header in the source tree -- `lib/libc/Makefile:105`
    # installs it into /usr/include out of `libc/port/gen` as part of libc's
    # `install_h`, and libcMinimal does not run that. Take it from the source
    # directory instead, exactly as libnsl.nix does.
    "usr/src/lib/libc/port/gen"

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

  # See libm.nix for why BUILD.SO has to be redefined to call $(LD) directly,
  # and libnsl.nix for why crti.o/crtn.o then have to be named explicitly.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libc/port/gen")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
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
    cp libsecdb.so.1 "$out/lib/"
    ln -s libsecdb.so.1 "$out/lib/libsecdb.so"

    runHook postInstall
  '';
}
