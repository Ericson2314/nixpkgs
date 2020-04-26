{ stdenv, lib, fetchurl, fetchpatch, cmake, ninja, pkgconfig, libiconv, libintl
, zlib, curl, cairo, freetype, fontconfig, lcms, libjpeg, openjpeg
, withData ? true, poppler_data
, qt5Support ? false, qtbase ? null
, introspectionSupport ? false, gobject-introspection-tools ? null
, utils ? false, nss ? null
, minimal ? false, suffix ? "glib"
}:

assert introspectionSupport -> gobject-introspection-tools != null;

let
  version = "0.88.0"; # beware: updates often break cups-filters build, check texlive and scribusUnstable too!
  mkFlag = optset: flag: "-DENABLE_${flag}=${if optset then "on" else "off"}";
in
stdenv.mkDerivation rec {
  pname = "poppler-${suffix}";
  inherit version;

  src = fetchurl {
    url = "${meta.homepage}/poppler-${version}.tar.xz";
    sha256 = "1isns9s484irq9ir4hbhpyqf6af2xzswh2pfrvk1k9d5x423hidl";
  };

  outputs = [ "out" "dev" ];

  nativeBuildInputs = [
    cmake ninja pkgconfig
  ] ++ lib.optional introspectionSupport gobject-introspection-tools;

  buildInputs = [
    libiconv libintl
  ] ++ lib.optional withData poppler_data;

  # TODO: reduce propagation to necessary libs
  propagatedBuildInputs = [
    zlib freetype fontconfig libjpeg openjpeg
  ] ++ lib.optionals (!minimal) [
    cairo lcms curl
  ] ++ lib.optional qt5Support qtbase
    ++ lib.optional utils nss;

  # Workaround #54606
  preConfigure = stdenv.lib.optionalString stdenv.isDarwin ''
    sed -i -e '1i cmake_policy(SET CMP0025 NEW)' CMakeLists.txt
  '';

  cmakeFlags = [
    (mkFlag true "UNSTABLE_API_ABI_HEADERS") # previously "XPDF_HEADERS"
    (mkFlag (!minimal) "GLIB")
    (mkFlag (!minimal) "CPP")
    (mkFlag (!minimal) "LIBCURL")
    (mkFlag utils "UTILS")
    (mkFlag qt5Support "QT5")
  ];

  meta = with lib; {
    homepage = "https://poppler.freedesktop.org/";
    description = "A PDF rendering library";

    longDescription = ''
      Poppler is a PDF rendering library based on the xpdf-3.0 code
      base. In addition it provides a number of tools that can be
      installed separately.
    '';

    license = licenses.gpl2;
    platforms = platforms.all;
    maintainers = with maintainers; [ ttuegel ] ++ teams.freedesktop.members;
  };
}
