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
  prependToVar makeFlags "MANDIR=${!outputMan}/share/man"
}

fixIllumosInstallDirs() {
  find "$SRC" -name 'Makefile.*' -exec \
    sed -i -E \
      -e 's|/usr/include|${INCSDIR}|' \
      -e 's|/usr/bin|${BINDIR}|' \
      -e 's|/usr/lib|${LIBDIR}|' \
      {} \;
}

postUnpackHooks+=(setIllumosSourceDir)
postPatchHooks+=(cdIllumosPath fixIllumosInstallDirs)
preConfigureHooks+=(addIllumosMakeFlags)
