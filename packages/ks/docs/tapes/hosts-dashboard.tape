# Hosts dashboard — live system monitoring with host list
#
# Regenerate: nix run nixpkgs#vhs -- docs/tapes/hosts-dashboard.tape

Require ks

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 20
Set WindowBar Colorful
Set TypingSpeed 0

Type "ks --screenshot hosts"
Enter
Sleep 2s
Screenshot docs/screenshots/hosts-dashboard.png
