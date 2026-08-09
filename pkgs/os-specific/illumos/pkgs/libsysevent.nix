{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnvpair,
}:

# libsysevent.so.1 -- the client side of the system event framework: the
# `sysevent_post_event`/`sysevent_bind_handle` interface onto syseventd(8),
# and the newer event-channel interface (`sysevent_evc_bind`,
# `sysevent_evc_publish`) that talks to the kernel's sysevent channels
# directly through /dev/sysevent.
#
# It is here for `svc.startd`, which links `-lsysevent`, and for `librestart`,
# which links it too. Nothing publishes or subscribes usefully in this VM --
# syseventd is not packaged -- but the channel calls degrade to errors rather
# than requiring a daemon, and the symbols have to resolve.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libsysevent/amd64";
  pname = "libsysevent";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsysevent"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets its `-R`:
  # without it there is no DT_RUNPATH and no nix reference, so the dependency
  # is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnvpair}/lib -R${libnvpair}/lib \$(LDLIBS)")
  '';

  # <libsysevent.h> is installed into /usr/include by the *top*
  # lib/libsysevent Makefile, which we do not run: we build the amd64
  # subdirectory directly. `libsysevent_impl.h` goes with it, as upstream
  # installs both.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libsysevent.so.1 "$out/lib/"
    ln -s libsysevent.so.1 "$out/lib/libsysevent.so"

    mkdir -p "$dev/include"
    cp ../libsysevent.h ../libsysevent_impl.h "$dev/include/"

    runHook postInstall
  '';
}
