{
  lib,
  pkgs,
  windows-fonts,
  windowsFontsPackage ? windows-fonts,
  qtImModule ? "fcitx",
}: let
  wpsFontsConf = pkgs.writeText "wps-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <reset-dirs />
      <dir>${windowsFontsPackage}/share/fonts</dir>
    </fontconfig>
  '';

  # Suppress bare Alt menu hints inside WPS; keep Alt combinations and niri bindings.
  wpsAltFilter =
    pkgs.runCommand "wps-alt-filter" {
      nativeBuildInputs = [pkgs.stdenv.cc];
    } ''
      mkdir -p "$out/lib"
      $CXX -std=c++17 -O2 -shared -fPIC -Wall -Wextra -Werror \
        -DQT_NAMESPACE=kso_qt -DQT_NO_VERSION_TAGGING \
        -isystem ${lib.getDev pkgs.libsForQt5.qtbase}/include \
        -o "$out/lib/libwps-alt-filter.so" -x c++ - -x none -ldl <<'CPP'
      #include <QtWidgets/QApplication>
      #include <QtGui/QKeyEvent>
      #include <cstdio>
      #include <cstdlib>
      #include <dlfcn.h>

      namespace kso_qt {
      bool QApplication::notify(QObject *receiver, QEvent *event) {
          if (event->type() == QEvent::KeyPress ||
              event->type() == QEvent::KeyRelease ||
              event->type() == QEvent::ShortcutOverride) {
              const auto *key = static_cast<QKeyEvent *>(event);
              if (key->key() == Qt::Key_Alt) {
                  event->accept();
                  return true;
              }
          }

          using Notify = bool (*)(QApplication *, QObject *, QEvent *);
          // WPS loads Qt with RTLD_LOCAL, outside RTLD_NEXT's lookup scope.
          static const auto original = [] {
              void *widgets = dlopen("libQt5WidgetsKso.so.5", RTLD_LAZY | RTLD_NOLOAD);
              return widgets ? reinterpret_cast<Notify>(dlsym(
                  widgets, "_ZN6kso_qt12QApplication6notifyEPNS_7QObjectEPNS_6QEventE"))
                  : nullptr;
          }();
          if (!original) {
              std::fputs("WPS Alt filter: bundled Qt notify function not found\n", stderr);
              std::abort();
          }
          return original(this, receiver, event);
      }
      }
      CPP
    '';

  # Reap daemonized cloud helpers when the foreground WPS launcher exits.
  wpsSession = pkgs.writeShellScript "wps-session" ''
    environment=()
    while IFS= read -r -d "" entry; do
      name="''${entry%%=*}"
      if [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        environment+=("--setenv=$name")
      fi
    done < <(${pkgs.coreutils}/bin/env -0)

    exec ${pkgs.systemd}/bin/systemd-run \
      --user --collect --quiet --wait --pipe --same-dir \
      --service-type=exec --description="WPS Office" \
      --property=ExitType=main \
      --property=KillMode=control-group \
      --property=TimeoutStopSec=10s \
      --expand-environment=no \
      "''${environment[@]}" -- "$@"
  '';

  # WPS bundles its own Qt stack and may fail to pick up input method settings
  # in some Wayland/XWayland setups. Wrap launchers explicitly for IME env.
  wrappedWpsPackage = pkgs.wpsoffice-cn.overrideAttrs (old: {
    # WPS versions follow nixpkgs; its source-tree updater is not a runnable app.
    passthru = builtins.removeAttrs (old.passthru or {}) ["updateScript"];
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeWrapper];
    postFixup =
      (old.postFixup or "")
      + ''
        for bin in wps wpp et wpspdf; do
          if [ -x "$out/bin/$bin" ]; then
            mv "$out/bin/$bin" "$out/bin/.$bin-wrapped"
            makeWrapper "${wpsSession}" "$out/bin/$bin" \
              --add-flags "$out/bin/.$bin-wrapped" \
              --set QT_QPA_PLATFORM "xcb" \
              --set QT_IM_MODULE "${qtImModule}" \
              --set GTK_IM_MODULE "fcitx" \
              --set XMODIFIERS "@im=${qtImModule}" \
              --set FONTCONFIG_FILE "${wpsFontsConf}" \
              --prefix LD_PRELOAD : "${wpsAltFilter}/lib/libwps-alt-filter.so"
          fi
        done

        # Menu and MIME launches must use the wrappers above.
        sed -i -E \
          "s#^(Exec|TryExec)=(wps|wpp|et|wpspdf)([[:space:]]|$)#\\1=$out/bin/\\2\\3#" \
          "$out/share/applications/"*.desktop
      '';
  });
in
  wrappedWpsPackage
