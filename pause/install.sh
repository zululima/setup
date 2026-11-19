#!/usr/bin/env bash

# Puts pause and resume on the PATH as links to pause.sh in ~/.local/bin, which
# the shell's PATH has to list.

set -eu

dir="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"
mkdir -p "$bin"
chmod +x "$dir/pause.sh"
for name in pause resume; do
  ln -sfn "$dir/pause.sh" "$bin/$name"
done
command -v pause > /dev/null || echo "add $bin to PATH"
