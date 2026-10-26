{
  lib,
  pkgs,
}:
# Baidu still links this ABI, removed from nixpkgs in August 2026.
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "gtkmm";
  version = "2.24.5";
  src = pkgs.fetchurl {
    url = "mirror://gnome/sources/gtkmm/2.24/gtkmm-${finalAttrs.version}.tar.xz";
    hash = "sha256-BoClO3v5C05L9ETR2J5t9Bx3fgusyW6cCfxN0vX+a3I=";
  };
  outputs = ["out" "dev"];
  nativeBuildInputs = [pkgs.pkg-config];
  propagatedBuildInputs = with pkgs; [gtk2 glibmm_2_4 atkmm cairomm_1_0 pangomm_1_4];
  enableParallelBuilding = true;
  doCheck = true;
  meta = {
    description = "Legacy C++ GTK2 bindings required by Baidu Netdisk";
    homepage = "https://gtkmm.gnome.org/";
    license = lib.licenses.lgpl2Plus;
    platforms = lib.platforms.linux;
  };
})
