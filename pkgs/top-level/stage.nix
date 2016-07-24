/* This file composes a single bootstrapping phase of the Nix Packages
   collection. That is, it imports the functions that build the various
   packages, and calls them with appropriate arguments. The result is a set of
   all the packages in the Nix Packages collection for some particular platform
   for some particular phase.

   Default arguments are only provided for bootstrapping
   arguments. Normal users should not import this directly but instead
   import `pkgs/default.nix` or `default.nix`. */


{ # The system (e.g., `i686-linux') for which to build the packages.
  system

, # The standard environment to use.
  stdenv

, # Disabled only for bootstrapping
  allowCustomOverrides ? true

, # Non-GNU/Linux OSes are currently "impure" platforms, with their libc
  # outside of the store.  Thus, GCC, GFortran, & co. must always look for
  # files in standard system directories (/usr/include, etc.)
  noSysDirs ? (system != "x86_64-freebsd" && system != "i686-freebsd"
               && system != "x86_64-solaris"
               && system != "x86_64-kfreebsd-gnu")

, # Allow a configuration attribute set to be passed in as an
  # argument.
  config

, crossSystem
, platform
, lib
, mkPackages
}:

let
  # Allow packages to be overridden globally via the `packageOverrides'
  # configuration option, which must be a function that takes `pkgs'
  # as an argument and returns a set of new or overridden packages.
  # The `packageOverrides' function is called with the *original*
  # (un-overridden) set of packages, allowing packageOverrides
  # attributes to refer to the original attributes (e.g. "foo =
  # ... pkgs.foo ...").
  configOverrider = self: config.packageOverrides or (super: {});

  # Return the complete set of packages, after applying the overrides
  # returned by the `overrider' function (see above).  Warning: this
  # function is very expensive!
  pkgsWithOverrides = overrider:
    let
      stdenvAdapters = self: super:
        let res = import ../stdenv/adapters.nix self; in res // {
          stdenvAdapters = res;
        };

      trivialBuilders = self: super:
        (import ../build-support/trivial-builders.nix {
          inherit lib; inherit (self) stdenv; inherit (self.xorg) lndir;
        });

      stdenvDefault = let
          stdenv_ = stdenv;
          changer = config.replaceStdenv or null;
        in { stdenv = stdenv_ // { inherit platform; }; };

      allPackagesArgs = {
        inherit system noSysDirs config crossSystem platform lib
          pkgsWithOverrides mkPackages;
      };
      allPackages = self: super:
        let res = import ./all-packages.nix allPackagesArgs res self;
        in res;

      aliases = self: super: import ./aliases.nix super;

      # stdenvOverrides is used to avoid circular dependencies for building
      # the standard build environment. This mechanism uses the override
      # mechanism to implement some staged compilation of the stdenv.
      #
      # We don't want stdenv overrides in the case of cross-building, or
      # otherwise the basic overridden packages will not be built with the
      # crossStdenv adapter.
      stdenvOverrides = self: super:
        lib.optionalAttrs (crossSystem == null && super.stdenv ? overrides)
          (super.stdenv.overrides super);

      customOverrides = self: super:
        lib.optionalAttrs allowCustomOverrides (overrider self super);
    in
      lib.fix' (
        lib.extends customOverrides (
          lib.extends stdenvOverrides (
            lib.extends aliases (
              lib.extends allPackages (
                lib.extends trivialBuilders (
                  lib.extends stdenvAdapters (
                    self: stdenvDefault)))))));
in
  pkgsWithOverrides configOverrider
