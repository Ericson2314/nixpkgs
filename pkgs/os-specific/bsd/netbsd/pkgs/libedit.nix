{
  mkDerivation,
  libterminfo,
  libcurses,
  compatIfNeeded,
  defaultMakeFlags,
}:

mkDerivation {
  path = "lib/libedit";
  buildInputs = [
    libterminfo
    libcurses
  ];
  propagatedBuildInputs = compatIfNeeded;
  SHLIBINSTALLDIR = "$(out)/lib";
  makeFlags = defaultMakeFlags ++ [ "LIBDO.terminfo=${libterminfo}/lib" ];
  postPatch = ''
    sed -i '1i #undef bool_t' $COMPONENT_PATH/el.h
    substituteInPlace $COMPONENT_PATH/config.h \
      --replace "#define HAVE_STRUCT_DIRENT_D_NAMLEN 1" ""
    substituteInPlace $COMPONENT_PATH/readline/Makefile --replace /usr/include "$out/include"
    # New in 11.0: a `libedit.pc` installed via an absolute `FILESDIR`, which
    # sidesteps the prefix entirely and tries to write to the real `/usr`.
    substituteInPlace $COMPONENT_PATH/Makefile \
      --replace-fail "FILESDIR_libedit.pc=	/usr/lib/pkgconfig" \
                     "FILESDIR_libedit.pc=	$out/lib/pkgconfig"
    substituteInPlace $COMPONENT_PATH/libedit.pc --replace-fail "prefix=/usr" "prefix=$out"
  '';
  env.NIX_CFLAGS_COMPILE = toString [
    "-D__noinline="
    "-D__scanflike(a,b)="
    "-D__va_list=va_list"
  ];
}
