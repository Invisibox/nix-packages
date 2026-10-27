{
  pkgs,
  jail,
}: let
  python = pkgs.python3.withPackages (p: [p.dbus-next]);
  probe = pkgs.writeShellApplication {
    name = "sandbox-probe";
    text = ''
      if [[ "$1" == ime ]]; then
        test "''${QT_IM_MODULE-unset}" = "$2"
        test "''${GTK_IM_MODULE-unset}" = "$3"
        test "''${XMODIFIERS-unset}" = "$4"
        exit 0
      fi
      test "$(cat "$HOME/Documents/readable")" = documents
      test ! -e "$HOME/.ssh/private"
      test ! -e "$HOME/Downloads/private"
      test ! -e "$HOME/Documents/escape/private"
      if touch "$HOME/Documents/forbidden" 2>/dev/null; then
        echo "Documents must be read-only" >&2
        exit 1
      fi
      touch "$HOME/persistent"
      ${pkgs.diffutils}/bin/cmp /usr/bin/xdg-open "$BROWSER"
      if ${pkgs.gnugrep}/bin/grep -Eq '@/?tmp/\.X11-unix/X42$' /proc/net/unix; then
        echo "The private X server must not expose an abstract socket" >&2
        exit 1
      fi
      "$BROWSER" 'https://example.org/?a=1&b=2'
      if "$BROWSER" "file://$HOME/.ssh/private" 2>/dev/null; then
        echo "File URLs must not leave the sandbox" >&2
        exit 1
      fi
      if ${pkgs.systemd}/bin/busctl --user call \
        org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
        org.freedesktop.portal.FileChooser OpenFile 'ssa{sv}' "" "" 0 2>/dev/null; then
        echo "FileChooser must be blocked even when the host service accepts it" >&2
        exit 1
      fi
      test ! -e /run/dbus/system_bus_socket
      test -s /etc/machine-id
      test -c /dev/video-jail-policy-probe
      : <> /dev/video-jail-policy-probe
      ${python}/bin/python ${./desktop-dbus.py} "$1"
    '';
  };
  desktop = pkgs.makeDesktopItem {
    name = "sandbox-probe";
    desktopName = "Sandbox probe";
    exec = "${probe}/bin/sandbox-probe";
  };
  application = pkgs.symlinkJoin {
    name = "sandbox-probe";
    version = "1";
    paths = [
      probe
      desktop
      (pkgs.writeShellScriptBin "wechat" ''exec ${probe}/bin/sandbox-probe "$@"'')
      (pkgs.writeShellScriptBin "qq" ''exec ${probe}/bin/sandbox-probe "$@"'')
    ];
    meta.description = "Sandbox permission probe";
  };
  wrapped = pkgs.callPackage ../packages/jailed-desktop/package.nix {
    inherit jail;
    pname = "jail-policy-probe";
    program = "sandbox-probe";
    package = application;
  };
  wechatWrapped = pkgs.callPackage ../packages/jailed-desktop/package.nix {
    inherit jail;
    pname = "jail-policy-wechat-probe";
    program = "wechat";
    package = application;
  };
  qqWrapped = pkgs.callPackage ../packages/jailed-desktop/package.nix {
    inherit jail;
    pname = "jail-policy-qq-probe";
    program = "qq";
    package = application;
  };
  fhsWrapped = pkgs.callPackage ../packages/jailed-desktop/package.nix {
    inherit jail;
    pname = "jail-policy-fhs-probe";
    program = "baidunetdisk";
    fhs = true;
    package = pkgs.buildFHSEnv {
      pname = "fhs-sandbox-probe";
      version = "1";
      executableName = "baidunetdisk";
      targetPkgs = p: [p.xdg-utils];
      runScript = "${probe}/bin/sandbox-probe";
      extraInstallCommands = ''
        mkdir -p "$out/share/applications"
        cp ${desktop}/share/applications/sandbox-probe.desktop "$out/share/applications/"
      '';
      meta.description = "FHS sandbox permission probe";
    };
  };
in
  pkgs.writeShellApplication {
    name = "test-jailed-desktop-policy";
    runtimeInputs = with pkgs; [coreutils dbus gnugrep systemd weston];
    text = ''
      if [[ "''${1-}" != --session ]]; then
        # Use /dev/null as a camera fixture, without opening real capture devices.
        exec timeout 60 dbus-run-session \
          --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- ${pkgs.bubblewrap}/bin/bwrap \
          --dev-bind / / --dev /dev \
          --dev-bind /dev/null /dev/video-jail-policy-probe "$0" --session
      fi
      test_root=$(mktemp -d)
      cleanup() {
        kill "''${weston_pid-}" "''${service_pid-}" 2>/dev/null || true
        rm -rf "$test_root"
      }
      trap cleanup EXIT
      mkdir -p "$test_root/home/"{Documents,.ssh,Downloads} "$test_root/runtime"
      chmod 700 "$test_root/runtime"
      printf documents > "$test_root/home/Documents/readable"
      touch "$test_root/home/.ssh/private" "$test_root/home/Downloads/private"
      ln -s ../.ssh "$test_root/home/Documents/escape"
      export XDG_RUNTIME_DIR="$test_root/runtime" WAYLAND_DISPLAY=wayland-test XDG_SESSION_TYPE=wayland
      session_bus_path="''${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
      ln -s "''${session_bus_path%%,*}" "$XDG_RUNTIME_DIR/bus"
      export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
      weston --no-config --backend=headless --renderer=pixman --shell=kiosk-shell.so \
        --socket="$WAYLAND_DISPLAY" --idle-time=0 >"$test_root/weston.log" 2>&1 &
      weston_pid=$!
      ${python}/bin/python ${./desktop-dbus.py} host >"$test_root/services.log" 2>&1 &
      service_pid=$!
      for _ in {1..100}; do
        if [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] &&
          grep -q READY "$test_root/services.log"; then
          break
        fi
        sleep 0.1
      done
      test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || { cat "$test_root/weston.log"; exit 1; }
      grep -q READY "$test_root/services.log" || { cat "$test_root/services.log"; exit 1; }
      # Prove the mock accepts the forbidden method before testing the proxy.
      busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
        org.freedesktop.portal.FileChooser OpenFile 'ssa{sv}' "" "" 0
      export QT_IM_MODULE=fcitx GTK_IM_MODULE=fcitx XMODIFIERS=@im=fcitx
      for launcher in ${wrapped}/bin/jail-policy-probe ${fhsWrapped}/bin/jail-policy-fhs-probe; do
        env -u TERM HOME="$test_root/home" LANG=C.UTF-8 "$launcher" settings
      done
      env -u TERM -u QT_IM_MODULE -u GTK_IM_MODULE \
        HOME="$test_root/home" LANG=C.UTF-8 ${wechatWrapped}/bin/jail-policy-wechat-probe tray
      for launcher in ${wrapped}/bin/jail-policy-probe ${wechatWrapped}/bin/jail-policy-wechat-probe ${qqWrapped}/bin/jail-policy-qq-probe ${fhsWrapped}/bin/jail-policy-fhs-probe; do
        env -u TERM -u QT_IM_MODULE -u GTK_IM_MODULE -u XMODIFIERS \
          HOME="$test_root/home" LANG=C.UTF-8 "$launcher" ime unset unset unset
        env -u TERM -u QT_IM_MODULE -u GTK_IM_MODULE XMODIFIERS=@im=fcitx \
          HOME="$test_root/home" LANG=C.UTF-8 "$launcher" ime unset unset @im=fcitx
        env -u TERM QT_IM_MODULE=ibus GTK_IM_MODULE=ibus XMODIFIERS=@im=ibus \
          HOME="$test_root/home" LANG=C.UTF-8 "$launcher" ime ibus ibus @im=ibus
        env -u TERM QT_IM_MODULE= GTK_IM_MODULE= XMODIFIERS= \
          HOME="$test_root/home" LANG=C.UTF-8 "$launcher" ime "" "" ""
      done
      test -f "$test_root/home/.local/share/jail.nix/home/jail-policy-probe/persistent"
      test -f "$test_root/home/.local/share/jail.nix/home/jail-policy-fhs-probe/persistent"
      test ! -e "$test_root/home/persistent"
      test ! -e "$test_root/home/Documents/forbidden"
      grep -Fx 'Exec=${wrapped}/bin/jail-policy-probe %U' \
        ${wrapped}/share/applications/sandbox-probe.desktop
      echo "Sandbox policy: input methods, filesystem, persistence, browser, notifications, camera, audio, theme changes and tray callbacks passed"
    '';
  }
