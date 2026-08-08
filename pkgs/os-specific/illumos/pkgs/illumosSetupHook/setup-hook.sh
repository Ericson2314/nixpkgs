setIllumosSourceDir() {
  sourceRoot=$PWD/$sourceRoot
  export SRC=$sourceRoot/usr/src
  cd "$sourceRoot"
}

# Makefile.master takes its primary compiler and link-editor from these rather
# than from $CC/$LD directly, and the indirection is load-bearing: SunPro make
# re-exports any macro it imported from the environment whenever the makefile
# reassigns it, and Makefile.master reassigns both CC and LD. A recursive
# $(MAKE) would otherwise see CC in its environment as the whole expanded
# `cw --tag target ... --` command line, and Makefile.master's
# `command -v $CC` would resolve to cw itself. See the comment above
# PRIMARY_CC_PATH in usr/src/Makefile.master.
exportIllumosToolEnv() {
  # Fall back to a bare tool name rather than the empty string. nixpkgs'
  # bintools-wrapper never exports $LD, and an *empty* value is worse here than
  # a merely imprecise one: Makefile.master passes the result through as
  # `--linker $(BUILD_LD)`, so an empty expansion makes cw swallow the
  # following `--primary` as the linker's argument and then fail with
  # "A primary compiler must be specified".
  export ILLUMOS_CC="${CC:-cc}"
  export ILLUMOS_LD="${LD:-ld}"
}

cdIllumosPath() {
  if [ -d "$COMPONENT_PATH" ]
    then sourceRoot=$sourceRoot/$COMPONENT_PATH
    cd "$COMPONENT_PATH"
  fi
}

addIllumosMakeFlags() {
  # No DESTDIR is needed when building with Nix
  prependToVar makeFlags "ROOT="
  prependToVar makeFlags "INCLUDEDIR=${!outputDev}/include"
  prependToVar makeFlags "BINDIR=${!outputBin}/bin"
  prependToVar makeFlags "LIBDIR=${!outputLib}/lib"
  prependToVar makeFlags "MANDIR=${!outputMan}/share/man"
}

fixIllumosInstallDirs() {
  find "$SRC" -name 'Makefile*' -exec \
    sed -i -E \
      -e 's|/usr/include|$(INCLUDEDIR)|' \
      -e 's|/usr/bin|$(BINDIR)|' \
      -e 's|/usr/lib|$(LIBDIR)|' \
      {} \;
}

includesPhase() {
  if make -Pp ${makefile:+-f $makefile} | grep '^install_h:' >/dev/null && [ -z "${skipIncludesPhase:-}" ]; then
    runHook preIncludes

    local flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray
    flagsArray+=(install_h)

    echoCmd 'includes flags' "${flagsArray[@]}"
    make ${makefile:+-f $makefile} "${flagsArray[@]}"

    runHook postIncludes
  fi
}

postUnpackHooks+=(setIllumosSourceDir)
# postPatch rather than preConfigure: several illumos packages set
# dontConfigure, which skips the preConfigure hooks entirely.
postPatchHooks+=(exportIllumosToolEnv cdIllumosPath fixIllumosInstallDirs)
preConfigureHooks+=(addIllumosMakeFlags)
preInstallHooks+=(includesPhase)
