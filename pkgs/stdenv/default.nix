# This file defines the various standard build environments.
#
# On Linux systems, the standard build environment consists of
# Nix-built instances glibc and the `standard' Unix tools, i.e., the
# Posix utilities, the GNU C compiler, and so on.  On other systems,
# we use the native C library.

{ system, allPackages, platform, config, crossSystem, lib } @ args:


let

  # The native (i.e., impure) build environment.  This one uses the
  # tools installed on the system outside of the Nix environment,
  # i.e., the stuff in /bin, /usr/bin, etc.  This environment should
  # be used with care, since many Nix packages will not build properly
  # with it (e.g., because they require GNU Make).
  inherit (import ./native args) stdenvNative;

  # The Nix build environment.
  inherit (import ./nix { inherit allPackages stdenvNative config lib; }) stdenvNix;

  inherit (import ./freebsd args) stdenvFreeBSD;

  # Linux standard environment.
  inherit (import ./linux args) stdenvLinux;

  inherit (import ./darwin args) stdenvDarwin;

  inherit (import ./cross args) stdenvCross;

  inherit (import ./custom args) stdenvCustom;

  changer = config.replaceStdenv or null;

  # Select the appropriate stdenv for the platform `system'.
in
    if crossSystem != null then stdenvCross else
    if changer != null then stdenvCustom else
    if system == "i686-linux" then stdenvLinux else
    if system == "x86_64-linux" then stdenvLinux else
    if system == "armv5tel-linux" then stdenvLinux else
    if system == "armv6l-linux" then stdenvLinux else
    if system == "armv7l-linux" then stdenvLinux else
    if system == "mips64el-linux" then stdenvLinux else
    if system == "powerpc-linux" then /* stdenvLinux */ stdenvNative else
    if system == "x86_64-darwin" then stdenvDarwin else
    if system == "x86_64-solaris" then stdenvNix else
    if system == "i686-cygwin" then stdenvNative else
    if system == "x86_64-cygwin" then stdenvNative else
    if system == "x86_64-freebsd" then stdenvFreeBSD else
    stdenvNative
