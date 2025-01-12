addIllumosMakeFlags() {
  prependToVar makeFlags "MANDIR=${!outputMan}/share/man"
}

setIllumosSrcVariable() {
  export SRC="$BSDSRCDIR/usr/src"
}

fixIllumosInstallDirs() {
  find "$SRC" -name 'Makefile.*' -exec \
    sed -i -E \
      -e 's|/usr/include|${INCSDIR}|' \
      -e 's|/usr/bin|${BINDIR}|' \
      -e 's|/usr/lib|${LIBDIR}|' \
      {} \;
}

includesPhase() {
  # Nuke this from BSD setup hook
  #
  # TODO: separate the "build package within monorepo of makefiles" part of the
  # rest of BSD setup hook, and share just that with illumos.
  :
}

preConfigureHooks+=(addIllumosMakeFlags)
postPatchHooks+=(setIllumosSrcVariable fixIllumosInstallDirs)
