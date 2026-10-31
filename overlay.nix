{jail-nix}: final: prev: let
  jail = jail-nix.lib.init final;
in
  prev.lib.packagesFromDirectoryRecursive {
    directory = ./packages;
    callPackage = final.newScope {
      inherit jail;
      inherit (prev) gamescope nautilus;
      gvfs = prev.gnome.gvfs;
    };
  }
