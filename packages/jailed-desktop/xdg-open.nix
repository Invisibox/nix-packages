{pkgs}:
pkgs.writeShellApplication {
  name = "xdg-open";
  text = ''
    if (( $# != 1 )); then
      echo "usage: xdg-open https://example.org" >&2
      exit 1
    fi
    case "$1" in
      http://*|https://*) ;;
      *) echo "Only HTTP(S) links may leave the sandbox" >&2; exit 1 ;;
    esac
    exec ${pkgs.systemd}/bin/busctl --user call \
      org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
      org.freedesktop.portal.OpenURI OpenURI 'ssa{sv}' "" "$1" 0 >/dev/null
  '';
}
