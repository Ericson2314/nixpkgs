{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnsl,
  # Headers only -- getauuser.c includes <bsm/libbsm.h> for the audit_user
  # table's structures. LDLIBS is just -lnsl -lc, so nothing is linked from it.
  libbsm,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libsocket,
  libmd,
  libmp,
}:

# nss_files.so.1 -- the "files" backend of the name-service switch, out of
# usr/src/lib/nsswitch/files. This is what actually reads /etc/passwd,
# /etc/shadow, /etc/group, /etc/hosts, /etc/services and the illumos-only
# RBAC tables.
#
# It is not optional the way a plugin usually is. libc resolves every switch
# lookup by dlopen()ing a backend by name -- see the NSS_DLOPEN_FORMAT
# "nss_%s.so.%d" in lib/libc/port/gen/nss_deffinder.c -- so with no backend on
# disk `getpwnam("root")` fails outright and nothing can turn a name into a
# uid. That defeats `login`, `getent`, and `sshd` all at once.
#
# sshd is the non-obvious one, and it is worth spelling out why nsswitch is on
# the critical path for ssh: nixpkgs builds openssh with `withPAM` defaulting
# to `isLinux`, so the illumos sshd is a *non*-PAM build. It does its own
# password authentication against /etc/shadow via getpwnam/getspnam, which
# means it depends on this backend directly rather than through a PAM stack.
#
# Note the shared object is `nss_files.so.1`, not `libnss_files.so.1`: the
# Makefile builds LIBRARY=libnss_files.a but overrides DYNLIB1, because the
# dlopen name has no `lib` prefix.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/nsswitch/files/amd64";
  pname = "nss-files";

  extraPaths = [
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/nsswitch"

    # tsol_getrhent.c and tsol_gettpent.c include <libtsnet.h>, which reaches
    # upstream builds only through the proto area -- lib/libtsnet's Makefile
    # installs it into /usr/include -- so take it from the source directory,
    # exactly as libinetutil.nix does for <libsocket_priv.h>.
    "usr/src/lib/libtsnet/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnsl
    libbsm
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for the BUILD.SO override and for the `-L`/`-R` rule these
  # lines follow.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libtsnet/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libsocket}/lib -R${libsocket}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp nss_files.so.1 "$out/lib/"

    runHook postInstall
  '';
}
