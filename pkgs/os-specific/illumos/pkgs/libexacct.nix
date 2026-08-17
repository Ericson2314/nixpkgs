{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libexacct.so.1 -- the reader/writer for extended accounting files: the
# self-describing tagged-record format that `acctadm`, and the task and flow
# accounting in the kernel, use for their output. `ea_open`/`ea_get_object`
# walk a file; `ea_pack_object` builds one.
#
# Packaged for the `ipadm`/`dladm` closure: flow accounting is part of the
# datalink stack, and libdladm carries libexacct for reading the flow
# accounting files that `flowadm` and `dladm show-*` report on. `libpool`
# links `-lexacct` as well, and `librestart` -- hence `svc.startd` -- links
# `-lpool`.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libexacct/amd64";
  pname = "libexacct";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/libexacct"

    # exacct_core.o is compiled straight out of the code shared with the
    # kernel; Makefile.com has its own pics rule reaching into it.
    "usr/src/common/exacct"

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

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  # No `dev` output: unlike most libraries here, libexacct's public headers
  # (<exacct.h>, <exacct_impl.h>) are not under lib/libexacct at all -- they
  # live in usr/src/head and so arrive through the `headers` package already.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libexacct.so.1 "$out/lib/"
    ln -s libexacct.so.1 "$out/lib/libexacct.so"

    runHook postInstall
  '';
}
