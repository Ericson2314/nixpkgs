{ lib, stdenv, llvm_meta, cmake, python3
, monorepoSrc, runCommand, fixDarwinDylibNames
, cxx-headers, libunwind, version
, enableShared ? !stdenv.hostPlatform.isStatic
, headersOnly ? false
}:


/*
  mkdir -p "$out/libcxx/src"
  cp -r ${monorepoSrc}/libcxx/cmake "$out/libcxx"
  cp -r ${monorepoSrc}/libcxx/include "$out/libcxx"
  cp -r ${monorepoSrc}/libcxx/src/include "$out/libcxx/src"
  patch -p1 -d $out/libcxx ${../libcxx/gnu-install-dirs.patch}
  patch -p1 -d $out/${pname} ${./gnu-install-dirs.patch}
*/

stdenv.mkDerivation rec {
  pname = "libcxxabi";
  inherit version;

  src = runCommand "${pname}-src-${version}" {} ''
    mkdir -p "$out"
    cp -r ${monorepoSrc}/cmake "$out"

    # Copy required libcxx directories
    cp -r ${monorepoSrc}/${pname} "$out"
    mkdir -p "$out/libcxx"
    cp -r ${monorepoSrc}/libcxx "$out"

    # Copy required dirs
    mkdir -p "$out/llvm"
    cp -r ${monorepoSrc}/llvm "$out"
    mkdir -p $out/third-party
    cp -r ${monorepoSrc}/third-party "$out"
    mkdir -p $out/runtimes
    cp -r ${monorepoSrc}/runtimes "$out"
    ls -la "$out/llvm"
  '';
  sourceRoot = "${src.name}/runtimes";

  outputs = [ "out" "dev" ];

  postUnpack = lib.optionalString stdenv.isDarwin ''
    export TRIPLE=x86_64-apple-darwin
  '' + lib.optionalString stdenv.hostPlatform.isWasm ''
    patch -p1 -d llvm -i ${./wasm.patch}
  '';

  preConfigure = lib.optionalString stdenv.hostPlatform.isMusl ''
    patchShebangs utils/cat_files.py
  '';

  nativeBuildInputs = [ cmake python3 ] ++ lib.optional stdenv.isDarwin fixDarwinDylibNames;
  buildInputs = lib.optional (!stdenv.isDarwin && !stdenv.isFreeBSD && !stdenv.hostPlatform.isWasm) libunwind;

  cmakeFlags = [
    # NOTE(cidkidnix): enable both libcxxabi and libcxx
    "-DLLVM_ENABLE_RUNTIMES=libcxxabi;libcxx"
    "-DLLVM_INCLUDE_TESTS=OFF"
    "-DLIBCXX_INCLUDE_BENCHMARKS=OFF"
  ] ++ lib.optionals (stdenv.hostPlatform.useLLVM or false) [
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DLIBCXXABI_USE_LLVM_UNWINDER=ON"
    "-DLIBCXX_USE_COMPILER_RT=ON"
  ] ++ lib.optionals stdenv.hostPlatform.isWasm [
    "-DLIBCXXABI_ENABLE_THREADS=OFF"
    "-DLIBCXXABI_ENABLE_EXCEPTIONS=OFF"
    "-DLIBCXX_ENABLE_THREADS=OFF"
    "-DLIBCXX_ENABLE_FILESYSTEM=OFF"
    "-DLIBCXX_ENABLE_EXCEPTIONS=OFF"
  ] ++ lib.optionals (!enableShared) [
    "-DLIBCXXABI_ENABLE_SHARED=OFF"
    "-DLIBCXX_ENABLE_SHARED=OFF"
  ] ++ lib.optional (stdenv.hostPlatform.isMusl || stdenv.hostPlatform.isWasi) "-DLIBCXX_HAS_MUSL_LIBC=1";

  passthru = {
    isLLVM = true;
  };

  meta = llvm_meta // {
    homepage = "https://libcxxabi.llvm.org/";
    description = "Provides C++ standard library support";
    longDescription = ''
      libc++abi is a new implementation of low level support for a standard C++ library.
    '';
    # "All of the code in libc++abi is dual licensed under the MIT license and
    # the UIUC License (a BSD-like license)":
    license = with lib.licenses; [ mit ncsa ];
    maintainers = llvm_meta.maintainers ++ [ lib.maintainers.vlstill ];
  };
}
