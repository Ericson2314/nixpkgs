{ stdenv, fetchurl, zlib }:

/* rustc nightly binary */

let nightlyDate = "2014-1-25";
in

with ((import ./common.nix) { inherit stdenv; version = "nightly-${nightlyDate}"; });

let nightlyHash = if stdenv.system == "i686-linux"
      then "0pnkhxncslyhnwqny8dpk4f7npnl4g7531hb3hiqxfj6qkbf6pkf"
#      else if stdenv.system == "x86_64-linux"
#      then
#      else if stdenv.system == "i686-darwin"
#      then
#      else if stdenv.system == "x86_64-darwin"
#      then
      else throw "no nightly for platform ${stdenv.system}";
in

stdenv.mkDerivation {
  inherit name;
  inherit version;
  inherit meta;

  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rust-nightly-${target}.tar.gz";
    sha256 = nightlyHash;
  };

  dontStrip = true;

  installPhase = ''
    mkdir -p "$out"
    mv bin   "$out/"
    mv lib   "$out/"
    mv share "$out/"
  '';

  preFixup = if stdenv.isLinux then ''
    set -v
    for e in $out/bin/*; do
      echo executable: $e
      patchelf --interpreter "${stdenv.glibc}/lib/${stdenv.cc.dynamicLinker}" \
               --set-rpath "$out/lib:${stdenv.cc.gcc}/lib/:${zlib}/lib" \
               "$e"
    done
    for l in $out/lib/*.so; do
      echo library: $l
      patchelf --set-rpath "$out/lib:${stdenv.cc.gcc}/lib/:${zlib}/lib" \
               "$l"
    done
  '' else "";
}
