{ stdenv
, fetchurl, meson, ninja, pkgconfig, glib, gobject-introspection-tools, flex
, bison, vala, gettext, gnome3, gtk-doc, docbook_xsl, docbook_xml_dtd_43
, gobject-introspection
}:

let
  version = "3.34.0";
  pname = "template-glib";
in

stdenv.mkDerivation {
  name = "${pname}-${version}";

  outputs = [ "out" "dev" "devdoc" ];

  src = fetchurl {
    url = "mirror://gnome/sources/${pname}/${stdenv.lib.versions.majorMinor version}/${pname}-${version}.tar.xz";
    sha256 = "1z9xkin5fyfh071ma9y045jcw83hgx33dfbjraw6cxk0qdmfysr1";
  };

  nativeBuildInputs = [
    meson ninja pkgconfig gettext flex bison vala glib gtk-doc docbook_xsl docbook_xml_dtd_43 gobject-introspection-tools
  ];

  buildInputs = [
    glib gobject-introspection
  ];

  mesonFlags = [
    "-Denable_gtk_doc=true"
  ];

  passthru = {
    updateScript = gnome3.updateScript {
      packageName = pname;
    };
  };

  meta = with stdenv.lib; {
    description = "A library for template expansion which supports calling into GObject Introspection from templates";
    homepage = "https://gitlab.gnome.org/GNOME/template-glib";
    license = licenses.lgpl21Plus;
    maintainers = teams.gnome.members;
    platforms = platforms.unix;
  };
}
