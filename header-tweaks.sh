#!/bin/bash

set -euo pipefail

scriptDir=$(readlink -nf "$(dirname "$0")")
cd "$scriptDir"

mkdir -p "./include"
rsync -rI --delete "/usr/include/glib-2.0/" "/usr/include/gtk-3.0/" "./include/"
patch -p0 < "./header-tweaks.patch"
