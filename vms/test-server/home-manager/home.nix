{ config, pkgs, ... }:

# Test configuration for terminal-dev-environment module
# Used by bin/test-home-manager for automated testing as testuser
# The module is copied to the VM, so we use a relative path
{
  imports = [ ./terminal-dev-environment ];

  home.username = "testuser";
  home.homeDirectory = "/home/testuser";
  home.stateVersion = "25.05";

  programs.terminal-dev-environment.enable = true;

  programs.git = {
    userName = "Test User";
    userEmail = "testuser@keystone-test-vm";
  };

  programs.home-manager.enable = true;
}
