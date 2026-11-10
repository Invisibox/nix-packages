{
  jail-nix,
  chinese-fonts-overlay,
}: final: prev: let
  jail = jail-nix.lib.init final;
in
  prev.lib.packagesFromDirectoryRecursive {
    directory = ./packages;
    callPackage = final.newScope {
      inherit jail;
      inherit (prev) bottles gamescope nautilus;
      gvfs = prev.gnome.gvfs;
      windows-fonts = chinese-fonts-overlay.packages.${final.stdenv.hostPlatform.system}.windows-fonts;
    };
  }
