{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  sgs-libelf,
  sgs-librtld_db,
  libctf,
  libuutil,
}:

# libproc.so.1 -- the process-control library behind the /proc tools: the
# `Pgrab`/`Pcreate` handle interface, symbol table and stack walking
# (`Psymtab`, `Pstack`), core file reading and writing (`Pcore`, `Pgcore`),
# and the `pr_*` shims that run a system call in the *controlled* process
# rather than in the caller. `pgrep`, `pstack`, `truss` and mdb all sit on it.
#
# Here only as a dependency: `libproject` links `-lproc`, `librestart` links
# `-lproject`, and `svc.startd` links `-lrestart`. startd itself does not
# grab processes -- it uses contracts for that -- so nothing in this chain
# needs /proc to work for a service to start.
#
# Its three link dependencies are all already packaged for the target:
# `sgs-libelf` and `libctf` for reading symbol and CTF data out of objects,
# and `sgs-librtld_db` for walking another process's link map.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libproc/amd64";
  pname = "libproc";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libproc"

    # `CPPFLAGS += -I$(SRC)/common/core`, and core_shstrtab.o is compiled out
    # of there: the core-file section-header string table is shared with the
    # kernel's core dump code.
    "usr/src/common/core"

    # list.o is compiled out of the shared list implementation.
    "usr/src/common/list"

    # Pzone.c includes <libzonecfg.h>, which includes <libbrand.h>; that one
    # reaches upstream builds only through the proto area, so take it from the
    # source directory exactly as libscf.nix does. Header dependency only --
    # nothing here links -lbrand or -lzonecfg.
    "usr/src/lib/libbrand/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    sgs-libelf
    sgs-librtld_db
    libctf
    # Header-only: <libzonecfg.h>, reached from Pzone.c, includes
    # <libuutil.h>. Nothing here links -luutil.
    libuutil
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
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libbrand/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${sgs-librtld_db}/lib -R${sgs-librtld_db}/lib -L${sgs-libelf}/lib -R${sgs-libelf}/lib -L${libctf}/lib -R${libctf}/lib \$(LDLIBS)")
  '';

  # <libproc.h> is installed into /usr/include by the *top* lib/libproc
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libproc.so.1 "$out/lib/"
    ln -s libproc.so.1 "$out/lib/libproc.so"

    mkdir -p "$dev/include"
    cp ../common/libproc.h "$dev/include/"

    runHook postInstall
  '';
}
