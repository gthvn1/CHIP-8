#!/usr/bin/env bash
set -ex

build_emulator() {
  # Build the shared library
  # Note: when building the destination is open and then write is not atomic. So
  #       if we don't take care we will see "host" that tries to read a partial
  #       file and fails to load it. To avoid that we compile using a tmp file
  #       and we move it once done. As we are using -e if an error happens we exit.
  #       And mv is atomic.
  odin build emulator -build-mode:dll -debug -out:temp/chip8-temp.so -vet -strict-style
  mv temp/chip8-temp.so temp/chip8.so
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
  emu) build_emulator ;;
  host) build_host ;;
  all)  build_emulator; build_host ;;
  *)    echo "Usage: $0 {emu|host|all}" >&2; exit 1 ;;
esac

# Some useful commands:
#
# nm -D chip8.so | grep render
# nm -D host | grep render
# nm -D /nix/store/...-glibc-2.44-57/lib/libc.so.6 | grep ' dlopen'
#
# readelf -d host | grep NEEDED
# objdump -d host | grep -A3 '<dlopen@plt>'
#
# LD_DEBUG=bindings ./host 2>&1 | grep dlopen
# grep chip8 /proc/$(pidof host)/maps
# ls -i chip8.so
#
# gdb -p $(pidof host)
