{
  callPackage,
  jail,
  qq,
}:
callPackage ../../lib/jailed-desktop/package.nix {
  inherit jail;
  package = qq;
  pname = "qq-jailed";
  program = "qq";
}
