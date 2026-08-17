#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"

while IFS= read -r script; do
  bash -n "${script}"
done < <(find "${script_dir}" -maxdepth 1 -type f -name '*.sh' -print | sort)

echo "Release shell scripts parse cleanly."
