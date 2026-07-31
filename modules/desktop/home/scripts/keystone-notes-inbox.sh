#!/usr/bin/env bash

set -euo pipefail

exec ghostty --title="keystone-notes-inbox" -e zk --notebook-dir "$HOME/notes" edit -i
