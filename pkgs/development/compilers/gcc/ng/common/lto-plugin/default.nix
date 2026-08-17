{
  lib,
  stdenv,
  gcc_meta,
  release_version,
  version,
  monorepoSrc ? null,
  autoreconfHook269,
  libiberty,
}:
# THE LINKER PLUGIN, WITHOUT WHICH NO SHARED LIBRARY LINKS IN THIS SET.
#
# `lto-plugin` is a top-level `host_module` (`Makefile.def:182`), and
# `install-gcc` depends on `install-lto-plugin` (`:430`). `gcc/Makefile.in` has
# **zero** references to `liblto_plugin`, so a build that runs only
# `gcc/configure && make` in `gcc/` -- which is what this package set does --
# never builds it. Same class as `libiberty`, `libcpp`, `libcody`,
# `libbacktrace` and `fixincludes`: a component the top level would have built
# as a sibling, which here has to be a derivation.
#
# HOW ITS ABSENCE PRESENTED, because it is nothing like "plugin missing".
# `libgcc.a` builds fine and `libgcc_s.so` then dies with
#
#     aarch64-...-ld.bfd: -plugin-opt=<...>/libexec/gcc/17.0.0/lto-wrapper:
#       error loading plugin: ... cannot open shared object file
#
# i.e. `ld` reporting that `lto-wrapper` is not a plugin. It is not: the driver
# emits `-plugin %(linker_plugin_file)` and `linker_plugin_file` is EMPTY, so
# `-plugin` consumes the next token on the line, which is the `-plugin-opt=`
# naming `lto-wrapper`. The driver anticipates exactly this --
# `gcc/gcc.cc:10246-10262` sets `linker_plugin_file_spec` from
# `find_a_file (&exec_prefixes, LTOPLUGINSONAME)` and its comment says an empty
# value "would have passed a bare -plugin with no argument -- the delivery route
# would have looked connected and produced a worse failure than the one it
# replaced". It is silent because the `fatal_error` beside it fires only when
# the user asked for `-fuse-linker-plugin` by name.
#
# ONE PER HOST, NOT PER TARGET. It is `ld`'s plugin: it runs on the machine the
# linker runs on, which is this compiler's host, and it is loaded for every
# target that compiler serves. `AC_CANONICAL_TARGET` in its `configure.ac` feeds
# only the install path, which is overridden below.
stdenv.mkDerivation (finalAttrs: {
  pname = "lto-plugin";
  inherit version;

  src = monorepoSrc;

  strictDeps = true;

  nativeBuildInputs = [ autoreconfHook269 ];

  autoreconfFlags = "--install --force --verbose . lto-plugin";

  postUnpack = ''
    mkdir -p ./build
    buildRoot=$(readlink -e "./build")
  '';

  postPatch = ''
    sourceRoot=$(readlink -e "./lto-plugin")
  '';

  enableParallelBuilding = true;

  # THE BOUNDARY, ENUMERATED. One sibling: libiberty, and it wants the **PIC**
  # variant. `lto-plugin/Makefile.am:40-52` looks for
  # `$(with_libiberty)/noasan/libiberty.a`, then `$(with_libiberty)/pic/
  # libiberty.a`, and falls back to `$(with_libiberty)/libiberty.a` -- linking
  # a non-PIC archive into a shared object, which fails on any target that
  # cares.
  #
  # This is the consumer of a defect already noted in `../libiberty`: libiberty
  # BUILDS `pic/libiberty.a` and `make install` ships only the non-PIC one, so
  # every consumer must either reach into a build tree or, as here, be handed a
  # directory shaped like one. `../libiberty` installs the PIC copy as
  # `libiberty_pic.a`; this puts it back under the name and subdirectory
  # `lto-plugin` looks for. Upstream's fix is for libiberty to install its PIC
  # variant properly.
  preConfigure = ''
    mkdir -p "$buildRoot/libiberty/pic"
    install -m644 "${libiberty}/lib/libiberty.a" "$buildRoot/libiberty/libiberty.a"
    install -m644 "${libiberty}/lib/libiberty_pic.a" "$buildRoot/libiberty/pic/libiberty.a"

    mkdir -p "$buildRoot/lto-plugin"
    cd "$buildRoot/lto-plugin"
    configureScript=$sourceRoot/configure
    chmod +x "$configureScript"
  '';

  configurePlatforms = [
    "build"
    "host"
  ];

  configureFlags = [
    "--disable-dependency-tracking"
    "--with-libiberty=${placeholder "out"}/../libiberty"
  ];

  # `--with-libiberty` has to be the BUILD-time directory, not a store path, and
  # `configureFlags` cannot name `$buildRoot`. Fix it up where the variable
  # exists.
  postConfigure = ''
    substituteInPlace Makefile \
      --replace-fail 'with_libiberty = ${placeholder "out"}/../libiberty' \
                     "with_libiberty = $buildRoot/libiberty"
    grep -q "with_libiberty = $buildRoot/libiberty" Makefile
  '';

  # `lto-plugin/Makefile.am:8` computes
  # `libexecsubdir := $(libexecdir)/gcc/$(real_target_noncanonical)/$(gcc_version)`
  # -- a TARGET component in the path of a host artefact, which on this branch
  # is wrong twice over: one compiler serves every back end, so its `libexec`
  # is `libexec/gcc/<version>/` with no triple, and `find_a_file` searches
  # exactly there. State the directory instead of letting the component compute
  # it, the same way `../gcc` states `itoolsdir` and `../fixincludes` states
  # `bindir`.
  installFlags = [
    "libexecsubdir=${placeholder "out"}/libexec/gcc/${release_version}"
  ];

  # Two checks, and the second is the one that can catch a plausible-looking
  # failure: `onload' is the entry point `ld' dlsym's, so a plugin that loads and
  # exports nothing is indistinguishable from a working one until a link
  # actually uses LTO.
  postInstall = ''
    so="$out/libexec/gcc/${release_version}/liblto_plugin.so"
    test -f "$so" || {
      echo "lto-plugin: $so was not installed." >&2
      echo "  libtool installs a -module as .so; if the name or the" >&2
      echo "  directory has moved, fix this path rather than dropping the" >&2
      echo "  check -- an absent plugin is not a build error anywhere, it is" >&2
      echo "  a bare -plugin on the link line that swallows the next" >&2
      echo "  argument." >&2
      ls -R "$out" >&2
      exit 1; }

    "''${NM:-nm}" --dynamic --defined-only "$so" | grep -qw onload || {
      echo "lto-plugin: $so exports no \`onload'." >&2
      exit 1; }
    echo "lto-plugin: installed $so, exports onload"
  '';

  meta = gcc_meta // {
    homepage = "https://gcc.gnu.org/";
    description = "GCC's LTO plugin for the linker";
  };
})
