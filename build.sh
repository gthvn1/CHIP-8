#!/usr/bin/env bash
set -ex

build_game() {
  # Build the shared library
  # Note: when building the destination is open and then write is not atomic. So
  #       if we don't take care we will see "host" that try to read a partial
  #       file and failed to load it. To avoid that we compile using a tmp file
  #       and we move it once done. As we are using -e if an error happens we exit.
  #       And mv is atomic.
  odin build game -build-mode:dll -debug -out:temp/game-temp.so -vet -strict-style
  mv temp/game-temp.so temp/game.so
}

build_host() {
  # Build the host.
  odin build host -debug -out:temp/host -vet -strict-style
}

# Ensure we are in the root dir
cd "$(dirname "$0")"

# Ensure that build directory exists
mkdir -p temp

case "$1" in
  game) build_game ;;
  host) build_host ;;
  all)  build_game; build_host ;;
  *)    echo "Usage: $0 {game|host|all}"; exit 1 ;;
esac

# Some useful commands:
#
# nm -D game.so | grep display
# nm -D host | grep display
# nm -D /nix/store/...-glibc-2.44-57/lib/libc.so.6 | grep ' dlopen'
# 
# readelf -d host | grep NEEDED
# objdump -d host | grep -A3 '<dlopen@plt>'
# 
# LD_DEBUG=bindings ./host 2>&1 | grep dlopen
# grep game /proc/$(pidof host)/maps
# ls -i game.so
# 
# gdb -p $(pidof host)
