final: prev: {
  dbus = prev.dbus.overrideAttrs (old: {
    mesonFlags =
      (old.mesonFlags or [])
      ++ final.lib.optionals final.stdenv.hostPlatform.isDarwin [
        # Avoid launchd activation so dbus-run-session works in build/test sandboxes.
        "-Ddbus_session_bus_listen_address=unix:tmpdir=/tmp"
      ];

    postInstall =
      (old.postInstall or "")
      + final.lib.optionalString final.stdenv.hostPlatform.isDarwin ''
        # Fix rpath-based dylib references for dbus binaries on Darwin.
        for exe in bin/dbus-daemon bin/dbus-run-session libexec/dbus-daemon-launch-helper; do
          install_name_tool "$out/$exe" \
            -change "@rpath/libdbus-1.3.dylib" "$lib/lib/libdbus-1.3.dylib"
        done
      '';
  });
}
