{jail-nix}: final: prev: let
  jail = jail-nix.lib.init final;
in {
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
  wechat-jailed = final.callPackage ./packages/wechat-jailed/package.nix {inherit jail;};
  qq-jailed = final.callPackage ./packages/qq-jailed/package.nix {inherit jail;};
  baidunetdisk-jailed = final.callPackage ./packages/baidunetdisk-jailed/package.nix {inherit jail;};
}
