setIllumosSourceDir() {
  sourceRoot=$PWD/$sourceRoot
  export SRC=$sourceRoot/usr/src
  cd "$sourceRoot"
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
postPatchHooks+=(cdIllumosPath fixIllumosInstallDirs)
preConfigureHooks+=(addIllumosMakeFlags)
preInstallHooks+=(includesPhase)
