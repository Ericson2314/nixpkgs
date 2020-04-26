{ lib, mkXfceDerivation, gobject-introspection-tools }:

mkXfceDerivation {
  category = "xfce";
  pname = "libxfce4util";
  version = "4.14.0";

  sha256 = "0vq16bzmnykiikg4dhiaj0qbyj76nkdd54j6k6n568h3dc9ix6q4";

  nativeBuildInputs = [ gobject-introspection-tools ];

  meta = with lib; {
    description = "Extension library for Xfce";
    license = licenses.lgpl2Plus;
  };
}
