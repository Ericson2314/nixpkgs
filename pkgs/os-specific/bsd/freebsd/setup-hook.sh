addFreeBSDMakeFlags() {
  makeFlags="SBINDIR=${!outputBin}/bin $makeFlags"
  makeFlags="LIBEXECDIR=${!outputLib}/libexec $makeFlags"
  makeFlags="INCLUDEDIR=${!outputDev}/include $makeFlags"
}

preConfigureHooks+=(addFreeBSDMakeFlags)
