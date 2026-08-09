{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libpam.so.1 -- the PAM framework itself, out of usr/src/lib/libpam. One
# object, pam_framework.o, and `LDLIBS += -lc`: it is only the dispatcher that
# reads /etc/pam.conf and dlopen()s the modules named there. All the policy
# lives in the modules, none of which are packaged.
#
# It is here because the real /sbin/init links `-lpam -lbsm -lcontract -lscf`.
# That sounds like it should drag in login(1)'s whole authentication stack, and
# it does not: init's entire use of PAM is `notify_pam_dead()` (cmd/init/init.c
# 2577-2596), which runs on utmpx session *teardown* and does
#
#     pam_start("init", user, NULL, &pamh)
#     pam_set_item(pamh, PAM_TTY, ...)  /  pam_set_item(pamh, PAM_RHOST, ...)
#     pam_close_session(pamh, 0)
#     pam_end(pamh, PAM_SUCCESS)
#
# and nothing else -- no pam_authenticate, no pam_acct_mgmt, no
# pam_open_session. Every return value is cast to (void), so a stack that fails
# or is absent changes nothing an operator would notice. init therefore needs
# the framework to link against and an /etc/pam.conf to read; it does not need
# a working session module.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libpam/amd64";
  pname = "libpam";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libpam"

    "usr/src/common/mapfiles"
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

  # pam_framework.c includes its own headers as <security/pam_appl.h>, but they
  # sit flat in lib/libpam -- upstream only ever sees them at that path because
  # the library's own Makefile installs them into the proto area's
  # /usr/include/security first. Nothing installs anything here, so build the
  # directory the include expects.
  preConfigure = ''
    mkdir -p ../security
    cp ../pam_appl.h ../pam_modules.h ../pam_impl.h ../security/
  '';

  # See libm.nix for the BUILD.SO override and the `-L`/`-R` rule. There are no
  # `-R`s here because there is nothing to record: LDLIBS is just `-lc`, so the
  # only `-L`s are the bootstrap libc and libssp_ns, which deliberately stay
  # bare.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I..")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libpam.so.1 "$out/lib/"
    ln -s libpam.so.1 "$out/lib/libpam.so"

    mkdir -p "$dev/include/security"
    cp ../pam_appl.h ../pam_modules.h ../pam_impl.h "$dev/include/security/"

    runHook postInstall
  '';
}
