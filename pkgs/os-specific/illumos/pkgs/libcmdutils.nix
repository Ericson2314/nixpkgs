{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libavl,
  libnvpair,
  # libnvpair.so.1 carries libnsl as a DT_NEEDED (it serialises with XDR), and
  # libnsl in turn carries libmd/libmp; the illumos link-editor insists on
  # finding a shared object's own dependencies on the link path.
  libnsl,
  libmd,
  libmp,
}:

# libcmdutils.so.1 -- the private grab-bag shared by the file-manipulating
# commands: the AVL tree of already-visited (device, inode) pairs that keeps
# `cp -r`/`mv` from looping through a cycle, extended-attribute copying,
# `writefile`, uid/gid name lookup caches, and `nicenum` for human-readable
# byte counts.
#
# It is an implementation detail of the commands, not a stable interface, but
# it has to exist before those commands can link, so it is packaged alongside
# the rest of the `dladm`/`ipadm` closure.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libcmdutils/amd64";
  pname = "libcmdutils";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: the consumers live in /usr/bin but also in
    # /sbin, so the library goes to /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libcmdutils"

    # list.o is compiled out of the linked-list code shared with the kernel,
    # via Makefile.com's own `pics/%.o: $(COMDIR)/%.c` rule.
    "usr/src/common/list"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libavl
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. Every `-L` gets a matching `-R`: without it
  # there is no DT_RUNPATH and no nix reference, so the dependency is absent
  # from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libavl}/lib -R${libavl}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <libcmdutils.h> sits in the *top* lib/libcmdutils directory rather than
  # common/, and is installed by that Makefile's `HDRS`, which we do not run:
  # the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libcmdutils.so.1 "$out/lib/"
    ln -s libcmdutils.so.1 "$out/lib/libcmdutils.so"

    mkdir -p "$dev/include"
    cp ../libcmdutils.h "$dev/include/"

    runHook postInstall
  '';
}
