#!/usr/bin/env bash
set -e
mkdir -p build
odin build rune -out:build/rune -debug
echo "Launching Rune ..."
./build/rune
