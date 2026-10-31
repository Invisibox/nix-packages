{
  lib,
  pkgs,
  jail,
  package,
  pname,
  program,
  fhs ? false,
}: let
  browserOpener = pkgs.callPackage ./xdg-open.nix {};
  # Inner FHS environments supply their own /usr/bin/xdg-open.
  application =
    if fhs
    then package.overrideAttrs (_: {extraBwrapArgs = ["--ro-bind ${browserOpener}/bin/xdg-open ${pkgs.xdg-utils}/bin/xdg-open"];})
    else package;
  permissions = with jail.combinators; [
    network
    (persist-home pname)
    (readonly (noescape ''"$HOME/Documents"''))
    (unsafe-add-raw-args "--chdir ~")
    (unsafe-add-raw-args ''--symlink "$HOME/.machine-id" /etc/machine-id'')
    wayland
    pulse
    pipewire
    camera
    (set-env "DISPLAY" ":42")
    # Disable the shared abstract socket and wait before starting X11 clients.
    (wrap-entry (entry: ''
      ${pkgs.dbus}/bin/dbus-uuidgen --ensure="$HOME/.machine-id"
      mkdir -m 1777 /tmp/.X11-unix
      ${lib.getExe pkgs.xwayland-satellite} :42 -nolisten local -nolisten tcp &
      satellite_pid=$!
      for _ in {1..100}; do
        if [[ -S /tmp/.X11-unix/X42 ]]; then
          exec ${entry}
        fi
        kill -0 "$satellite_pid"
        sleep 0.1
      done
      echo "Sandbox Xwayland failed to become ready" >&2
      exit 1
    ''))
    (runtime-deep-ro-bind "/etc/fonts")
    (runtime-deep-ro-bind "/run/current-system/sw/share/fonts")
    (runtime-deep-ro-bind "/run/opengl-driver")
    (try-readonly "/sys/dev/char")
    (try-readonly "/sys/devices")
    (unsafe-add-raw-args "--dev-bind-try /dev/dri /dev/dri")
    (add-pkg-deps [pkgs.xdg-utils browserOpener])
    (ro-bind "${browserOpener}/bin/xdg-open" "/usr/bin/xdg-open")
    (set-env "BROWSER" "${browserOpener}/bin/xdg-open")
    (set-env "TERM" (noescape ''"''${TERM:-dumb}"''))
    (set-env "LANG" (noescape ''"''${LANG:-C.UTF-8}"''))
    (set-env "XDG_CONFIG_HOME" (noescape ''"$HOME/.config"''))
    (set-env "XDG_CACHE_HOME" (noescape ''"$HOME/.cache"''))
    (set-env "XDG_DATA_HOME" (noescape ''"$HOME/.local/share"''))
    (set-env "XDG_STATE_HOME" (noescape ''"$HOME/.local/state"''))
    (set-env "XDG_DATA_DIRS" "${application}/share:${pkgs.hicolor-icon-theme}/share")
    (set-env "NIXOS_OZONE_WL" "1")
    (set-env "QT_QPA_PLATFORM" "wayland;xcb")
    (compose (
      if program == "wechat"
      then [
        (set-env "GTK_IM_MODULE" "fcitx")
        (set-env "QT_IM_MODULE" "fcitx")
        (set-env "XMODIFIERS" "@im=fcitx")
        (set-env "SDL_IM_MODULE" "fcitx")
        (set-env "GLFW_IM_MODULE" "fcitx")
      ]
      else map try-fwd-env ["QT_IM_MODULE" "GTK_IM_MODULE" "XMODIFIERS"]
    ))
    (dbus {
      # Qt's legacy tray names use hyphens, outside a narrower D-Bus subtree.
      own = lib.optionals (program == "wechat") ["org.kde.*"];
      talk = [
        "org.freedesktop.Notifications"
        "org.kde.StatusNotifierWatcher"
        "org.fcitx.Fcitx5"
      ];
      # Read settings and receive theme changes without granting file portals.
      call = [
        "org.freedesktop.portal.Desktop=org.freedesktop.portal.OpenURI.OpenURI@/org/freedesktop/portal/desktop"
        "org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.Read@/org/freedesktop/portal/desktop"
        "org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.ReadOne@/org/freedesktop/portal/desktop"
        "org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.ReadAll@/org/freedesktop/portal/desktop"
      ];
      broadcast = ["org.freedesktop.portal.Desktop=org.freedesktop.portal.Settings.SettingChanged@/org/freedesktop/portal/desktop"];
    })
  ];
  launcher = jail pname (lib.getExe' application program) permissions;
in
  pkgs.runCommand "${pname}-${package.version}" {
    inherit pname;
    inherit (package) version;
    meta =
      package.meta
      // {
        description = "${package.meta.description} (sandboxed with jail.nix)";
        mainProgram = pname;
        platforms = ["x86_64-linux"];
      };
  } ''
    mkdir -p "$out/bin" "$out/share/applications"
    ln -s ${launcher}/bin/${pname} "$out/bin/${pname}"
    ln -s ${pname} "$out/bin/${program}"
    if [ -d ${application}/share/icons ]; then
      ln -s ${application}/share/icons "$out/share/icons"
    fi
    for desktop in ${application}/share/applications/*.desktop; do
      target="$out/share/applications/$(basename "$desktop")"
      cp "$desktop" "$target"
      chmod u+w "$target"
      sed -i \
        -e "s|^Exec=.*|Exec=$out/bin/${pname} %U|" \
        -e "s|^TryExec=.*|TryExec=$out/bin/${pname}|" \
        -e 's|^DBusActivatable=.*|DBusActivatable=false|' \
        -e '/^Path=/d' "$target"
    done
  ''
