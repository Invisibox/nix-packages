{
  description = "Personal Nix packages for x86_64-linux";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";
  inputs.jail-nix.url = "sourcehut:~alexdavid/jail.nix";
  inputs.chinese-fonts-overlay = {
    url = "github:brsvh/chinese-fonts-overlay";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    jail-nix,
    chinese-fonts-overlay,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      # Baidu Netdisk still depends on GTK2.
      config.problems.handlers."gtk+".broken = "warn";
      overlays = [self.overlays.default];
    };
    packageNames = builtins.attrNames (self.overlays.default pkgs pkgs);
  in {
    overlays.default = import ./overlay.nix {inherit jail-nix chinese-fonts-overlay;};
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
