{ stdenv
, lib
, fetchurl
, fetchpatch
, gettext
, pkgconfig
, meson
, ninja
, gnome3
, glib
, gtk3
, gobject-introspection-tools
, vala
, libxml2
, gnutls
, gperf
, pango
, pcre2
, fribidi
, zlib
, icu
, systemd
}:

stdenv.mkDerivation rec {
  pname = "vte";
  version = "0.60.2";

  outputs = [ "out" "dev" ];

  src = fetchurl {
    url = "mirror://gnome/sources/${pname}/${stdenv.lib.versions.majorMinor version}/${pname}-${version}.tar.xz";
    sha256 = "19ccbw0yca78h5qcnm8claj4fg1pj68nj1fsjqqfpzhj7w72i81m";
  };

  passthru = {
    updateScript = gnome3.updateScript { packageName = pname; };
  };

  nativeBuildInputs = [
    gettext
    gobject-introspection-tools
    gperf
    libxml2
    meson
    ninja
    pkgconfig
    vala
  ];

  buildInputs = [
    fribidi
    gnutls
    pcre2
    zlib
    icu
    systemd
  ];

  propagatedBuildInputs = [
    # Required by vte-2.91.pc.
    gtk3
    glib
    pango
  ];

  patches =
    # VTE needs a small patch to work with musl:
    # https://gitlab.gnome.org/GNOME/vte/issues/72
    lib.optional
      stdenv.hostPlatform.isMusl
      (fetchpatch {
            name = "0001-Add-W_EXITCODE-macro-for-non-glibc-systems.patch";
            url = "https://gitlab.gnome.org/GNOME/vte/uploads/c334f767f5d605e0f30ecaa2a0e4d226/0001-Add-W_EXITCODE-macro-for-non-glibc-systems.patch";
            sha256 = "1ii9db9i5l3fy2alxz7bjfsgjs3lappnlx339dvxbi2141zknf5r";
      });

  postPatch = ''
    patchShebangs perf/*
    patchShebangs src/box_drawing_generate.sh
  '';

  meta = with stdenv.lib; {
    homepage = "https://www.gnome.org/";
    description = "A library implementing a terminal emulator widget for GTK";
    longDescription = ''
      VTE is a library (libvte) implementing a terminal emulator widget for
      GTK, and a minimal sample application (vte) using that.  Vte is
      mainly used in gnome-terminal, but can also be used to embed a
      console/terminal in games, editors, IDEs, etc. VTE supports Unicode and
      character set conversion, as well as emulating any terminal known to
      the system's terminfo database.
    '';
    license = licenses.lgpl2;
    maintainers = with maintainers; [ astsmtl antono lethalman ] ++ teams.gnome.members;
    platforms = platforms.unix;
  };
}
