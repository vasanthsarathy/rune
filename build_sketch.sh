#!/usr/bin/env bash
set -e
[ -z "$1" ] && { echo "Usage: ./build_sketch.sh <sketch-name>"; exit 1; }
mkdir -p build
odin build "sketches/$1" -out:"build/$1" -debug
echo "Running $1 ..."
"./build/$1"
