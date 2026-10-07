{
  lib,
  makeBinaryWrapper,
  python3,
  writeShellScript,
  emacsWithDoom,
}: let
  doom = emacsWithDoom.doomEmacs;
  emacs = emacsWithDoom.emacs;
  deps = doom.emacsWithPackages.deps;

  # macOS can lose the application's PID when a GUI launch execs through
  # Doom/emacsWithPackages wrappers. LaunchServices must start the real
  # bundled executable itself; pass the wrappers' environment via open.
  launch = writeShellScript "launch-doom-emacs-gui" ''
    exec /usr/bin/open -a ${lib.escapeShellArg "${emacs}/Applications/Emacs.app"} \
      --env "DOOMPROFILELOADFILE=$DOOMPROFILELOADFILE" \
      --env "DOOMPROFILE=$DOOMPROFILE" \
      --env "DOOMLOCALDIR=$DOOMLOCALDIR" \
      --env "DOOMDIR=$DOOMDIR" \
      --env "PATH=${deps}/bin:$PATH" \
      --env "EMACSLOADPATH=${deps}/share/emacs/site-lisp:''${EMACSLOADPATH-}" \
      --env "EMACSNATIVELOADPATH=${deps}/share/emacs/native-lisp:''${EMACSNATIVELOADPATH-}" \
      --env "emacsWithPackages_siteLisp=${deps}/share/emacs/site-lisp" \
      --env "emacsWithPackages_siteLispNative=${deps}/share/emacs/native-lisp" \
      --args --init-directory=${lib.escapeShellArg (toString doom.doomSource)} "$@"
  '';
in
  emacsWithDoom.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [makeBinaryWrapper python3];
    buildCommandPath = null;
    buildCommand = ''
      source ${old.buildCommandPath}

      makeWrapper ${launch} "$out/bin/emacs-gui" \
        ${lib.escapeShellArgs doom.makeWrapperArgs}
      ln -sf "$out/bin/emacs-gui" "$out/Applications/Emacs.app/Contents/MacOS/Emacs"

      # The transient launcher must not share the real Emacs application's
      # identity, otherwise LaunchServices can confuse their running instances.
      python3 - "$out/Applications/Emacs.app/Contents/Info.plist" <<'PY'
      import pathlib
      import plistlib
      import sys

      path = pathlib.Path(sys.argv[1])
      info = plistlib.loads(path.read_bytes())
      info["CFBundleIdentifier"] = "org.gnu.Emacs.doom-launcher"
      path.write_bytes(plistlib.dumps(info))
      PY
    '';
  })
