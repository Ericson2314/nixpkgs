{ stdenv, fetchurl, autoconf, automake, libtool, pkgconfig, gnome3
, gtk-doc, gtk2, lua, gobject-introspection-tools
, pythonSupport ? true, python2Packages ? null
}:

assert pythonSupport -> python2Packages != null;

let
  inherit (python2Packages) python pygtk;
in

stdenv.mkDerivation rec {
  pname = "keybinder";
  version = "0.3.0";

  src = fetchurl {
    name = "${pname}-${version}.tar.gz";
    url = "https://github.com/engla/keybinder/archive/v${version}.tar.gz";
    sha256 = "0kkplz5snycik5xknwq1s8rnmls3qsp32z09mdpmaacydcw7g3cf";
  };

  nativeBuildInputs = [
	autoconf automake gobject-introspection-tools
	libtool lua pkgconfig
  ] ++ stdenv.lib.optional pythonSupport python;
  buildInputs = [
    gnome3.gnome-common gtk-doc gtk2
  ] ++ stdenv.lib.optional pythonSupport pygtk;

  preConfigure = ''
    ./autogen.sh --prefix="$out"
  '';

  configureFlags = [
    (stdenv.lib.enableFeature pythonSupport "python")
  ];

  meta = with stdenv.lib; {
    description = "Library for registering global key bindings";
    longDescription = ''
      keybinder is a library for registering global keyboard shortcuts.
      Keybinder works with GTK-based applications using the X Window System.

      The library contains:

      * A C library, ``libkeybinder``
      * Gobject-Introspection (gir)  generated bindings
      * Lua bindings, ``lua-keybinder``
      * Python bindings, ``python-keybinder``
      * An ``examples`` directory with programs in C, Lua, Python and Vala.
    '';
    homepage = "https://github.com/engla/keybinder/";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    maintainers = [ maintainers.bjornfor ];
  };
}
