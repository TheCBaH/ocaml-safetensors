#!/usr/bin/env bash
set -euo pipefail
sudo -n unshare --net -- setpriv --reuid="$(id -u)" --regid="$(id -g)" --init-groups -- \
  env HOME="$HOME" PATH="$PATH" "$@"
