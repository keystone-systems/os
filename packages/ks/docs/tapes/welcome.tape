# Welcome screen — first-run experience showing import/create options
#
# Regenerate: nix run nixpkgs#vhs -- docs/tapes/welcome.tape
# NOTE: vhs Screenshot has trouble with sparse ratatui screens.
# Use the hosts-dashboard or create-config tapes as reference for working examples.

Require ks

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set WindowBar Colorful
Set TypingSpeed 0

Type "ks --screenshot welcome"
Enter
Sleep 2s
Screenshot docs/screenshots/welcome.png
