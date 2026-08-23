# REQ-032: Terminal product boundary

## Ownership

- **REQ-032.1** `ks.systems/os` MUST consume `ks.systems/terminal` as a flake
  input.
- **REQ-032.2** This repository MUST NOT export a terminal Home Manager module
  compatibility alias.
- **REQ-032.3** This repository MUST NOT export a terminal package
  compatibility alias.
- **REQ-032.4** The OS overlay MUST compose `terminal.overlays.default`.
- **REQ-032.5** The operating-system wrapper MUST share
  `terminal.homeModules.default` with managed Home Manager users.
- **REQ-032.6** OS modules MAY provide OS-owned packages through terminal
  integration options. They MUST NOT move editable terminal configuration
  back into the OS repository.

## Composition

- **REQ-032.7** The desktop input MUST follow the same terminal input that the
  OS wrapper consumes.
- **REQ-032.8** Desktop users MUST receive the terminal product through the
  desktop dependency.
- **REQ-032.9** Headless users MUST be able to enable the terminal product
  without the desktop product.
- **REQ-032.10** Consumer flakes MUST select host-specific options and
  dotfiles packages. The OS product MUST remain user-agnostic.

## Migration

- **REQ-032.11** Terminal modules, terminal-owned packages, primary terminal
  documents, and direct terminal checks MUST live in `ks.systems/terminal`.
- **REQ-032.12** OS-agent integration checks MAY remain here when they verify
  an OS service that consumes terminal options or packages.
