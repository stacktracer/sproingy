#!/bin/bash

set -euo pipefail

scriptDir=$(readlink -nf "$(dirname "$0")")
cd "$scriptDir"

mkdir -p "./include/"
rsync -rI --delete "/usr/include/glib-2.0/" "./include/glib-2.0/"
rsync -rI --delete "/usr/include/gtk-3.0/" "./include/gtk-3.0/"
patch -p0 < "./header-tweaks.patch"
