---
title: TUIs
description: Terminal user interfaces included in the Keystone terminal workflow
---

# TUIs

Keystone Terminal includes several terminal user interfaces as part of the
default workflow.

## Core TUIs

- Helix for editing
- Zellij for multiplexing and session layout
- Lazygit for Git workflows
- Yazi for file management

## Productivity and personal workflow TUIs

Depending on enabled modules, Keystone also includes:

- Himalaya for email
- Calendula for calendars
- Cardamum for contacts
- cfait for tasks
- Comodoro for timers

## Why Keystone uses TUIs

The Keystone terminal environment is designed to stay keyboard-first and to work
consistently across NixOS, macOS, and other Linux systems.

TUIs are a good fit because they:

- work locally and remotely,
- compose well inside Ghostty and Zellij, and
- preserve a similar workflow across graphical and headless machines.

## Related docs

- [Terminal Module](terminal.md)
- [Shell Tools](shell-tools.md)
