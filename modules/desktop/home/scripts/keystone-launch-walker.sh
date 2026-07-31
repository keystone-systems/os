#!/usr/bin/env bash

set -euo pipefail

# Simple wrapper for Walker with consistent menu dimensions
exec walker --width 1288 --maxheight 600 --minheight 600 "$@"
