{ stdenv, lib
, fetchFromGitLab, autoconf, automake, gtk-doc, libtool, pkgconfig, gobject-introspection-tools
, glib, libsoup
}:

stdenv.mkDerivation rec {
  version="0.5.0";
  pname = "uhttpmock";

  src = fetchFromGitLab {
    repo = "uhttpmock";
    owner = "uhttpmock";
    rev = version;
    sha256 = "0kkf670abkq5ikm3mqls475lydfsd9by1kv5im4k757xrl1br1d4";
  };

  nativeBuildInputs = [
    autoconf automake gtk-doc libtool pkgconfig gobject-introspection-tools
  ];

  buildInputs = [ glib libsoup ];

  preConfigure = "./autogen.sh";

  meta = with lib; {
    description = "Project for mocking web service APIs which use HTTP or HTTPS";
    homepage = "https://gitlab.com/groups/uhttpmock/";
    license = licenses.lgpl21;
    maintainers = with maintainers; [ ];
    platforms = with platforms; linux;
  };
}
