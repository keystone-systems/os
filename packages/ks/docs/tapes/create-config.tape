# Create config screen — new machine configuration form
#
# Regenerate: nix run nixpkgs#vhs -- docs/tapes/create-config.tape

Require ks

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set WindowBar Colorful
Set TypingSpeed 0

Type "ks --screenshot create-config"
Enter
Sleep 2s
Screenshot docs/screenshots/create-config.png
