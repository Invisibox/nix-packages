final: prev: {
  brave-origin-beta = final.callPackage ./packages/brave-origin-beta/package.nix {};
  paseo-desktop = final.callPackage ./packages/paseo-desktop/package.nix {};
  oxideterm = final.callPackage ./packages/oxideterm/package.nix {};
  neiro = final.callPackage ./packages/neiro/package.nix {};
  gamescope-patched = final.callPackage ./packages/gamescope-patched/package.nix {
    gamescope = prev.gamescope;
  };
  nautilus-with-extensions = final.callPackage ./packages/nautilus-with-extensions/package.nix {
    nautilus = prev.nautilus;
    gvfs = prev.gnome.gvfs;
  };
}
