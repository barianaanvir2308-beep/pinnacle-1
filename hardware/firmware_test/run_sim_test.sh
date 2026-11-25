#!/usr/bin/env bash
# Builds and runs sim_test.cpp: the ESP32 sketch on this computer with a fake board (needs a C++ compiler).
set -e
cd "$(dirname "$0")"
out="${TMPDIR:-/tmp}/pz_esp32_sim_test"
c++ -std=c++17 -Wall -Wextra -Wno-unused-parameter -o "$out" sim_test.cpp
"$out"
