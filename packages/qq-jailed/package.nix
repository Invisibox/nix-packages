{
  callPackage,
  jail,
  qq,
}:
callPackage ../jailed-desktop/package.nix {
  inherit jail;
  package = qq;
  pname = "qq-jailed";
  program = "qq";
}
