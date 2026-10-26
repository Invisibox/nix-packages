{
  description = "Personal Nix packages for x86_64-linux";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
  inputs.jail-nix.url = "sourcehut:~alexdavid/jail.nix";

  outputs = {
    self,
    nixpkgs,
    jail-nix,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [self.overlays.default];
    };
    packageNames = [
      "brave-origin-beta"
      "paseo-desktop"
      "oxideterm"
      "neiro"
      "gamescope-patched"
      "nautilus-with-extensions"
      "wechat-jailed"
      "qq-jailed"
      "baidunetdisk-jailed"
    ];
  in {
    overlays.default = import ./overlay.nix {inherit jail-nix;};
    packages.${system} = nixpkgs.lib.genAttrs packageNames (name: pkgs.${name});
    checks.${system} =
      self.packages.${system}
      // {
        jailed-desktop-policy = pkgs.callPackage ./tests/jailed-desktop.nix {
          jail = jail-nix.lib.init pkgs;
        };
      };
    formatter.${system} = pkgs.alejandra;
  };
}
