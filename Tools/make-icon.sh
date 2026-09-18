#!/bin/bash
# Convierte un PNG cuadrado en el ícono de la app.
#
#   ./Tools/make-icon.sh ~/Downloads/logo.png
#   ./build-app.sh
#
set -e
cd "$(dirname "$0")/.."
if [ -z "$1" ]; then
  echo "Uso: ./Tools/make-icon.sh <arte.png>"
  exit 1
fi
OUT=$(mktemp -d)
xcrun swiftc -O -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$OUT/make-icon" Tools/make-icon/main.swift
"$OUT/make-icon" "$1" UAMClass.icns
