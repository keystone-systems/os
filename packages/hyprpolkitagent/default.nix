{
  hyprpolkitagent,
  stdenv,
}:
hyprpolkitagent.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    sed -i '/setContextProperty("hpa", authState.qmlIntegration);/a\    authState.qmlEngine->rootContext()->setContextProperty("keystoneThemePath", qEnvironmentVariable("KEYSTONE_POLKIT_THEME"));' src/core/Agent.cpp

    cp ${./main.qml} qml/main.qml
  '';

  postInstall = (old.postInstall or "") + ''
    mv "$out/libexec/hyprpolkitagent" "$out/libexec/.hyprpolkitagent-keystone"
    cat > "$out/libexec/hyprpolkitagent" <<EOF
    #!${stdenv.shell}
    export KEYSTONE_POLKIT_THEME="''${KEYSTONE_POLKIT_THEME:-\$HOME/.config/keystone/current/polkit.json}"
    export QML_XHR_ALLOW_FILE_READ="''${QML_XHR_ALLOW_FILE_READ:-1}"
    # Force the Basic Quick Controls style. Without this, Qt picks the
    # Material style (or worse, falls back through the QQuickStyle
    # warning chain) which paints solid Material defaults over the
    # theme JSON and the dialog renders as a black box.
    export QT_QUICK_CONTROLS_STYLE="''${QT_QUICK_CONTROLS_STYLE:-Basic}"
    exec "$out/libexec/.hyprpolkitagent-keystone" "\$@"
    EOF
    chmod +x "$out/libexec/hyprpolkitagent"
  '';
})
