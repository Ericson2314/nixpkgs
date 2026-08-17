{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libofmt.so.1 -- the shared "output format" engine behind the column-oriented
# illumos commands. A caller hands `ofmt_open` a table of fields with widths
# and per-field callbacks; libofmt parses the `-o` field list, and then prints
# either the aligned human-readable columns or, under `-p`, the parsable
# colon-separated form with the right quoting.
#
# Packaged because `dladm` and `ipadm` are little more than a set of ofmt
# field tables over libdladm/libipadm: essentially every subcommand's output
# goes through here.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libofmt/amd64";
  pname = "libofmt";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: the commands that use ofmt live in /sbin, so
    # the library goes to /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libofmt"

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

  # `ofmt.c` includes its own <ofmt.h> with angle brackets and Makefile.com
  # adds no -I for it: upstream the header has already been installed into the
  # proto area by the top-level Makefile. Point at the source directory
  # instead.
  #
  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libofmt/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  # <ofmt.h> is installed by the *top* lib/libofmt Makefile (its `HDRS`),
  # which we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libofmt.so.1 "$out/lib/"
    ln -s libofmt.so.1 "$out/lib/libofmt.so"

    mkdir -p "$dev/include"
    cp ../common/ofmt.h "$dev/include/"

    runHook postInstall
  '';
}
