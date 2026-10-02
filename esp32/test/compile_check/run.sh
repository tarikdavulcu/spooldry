#!/bin/sh
# Syntax/type-checks the Arduino glue against mock headers that mirror the real library signatures.
# The real ESP32 build happens in CI (PlatformIO / arduino-cli), see .github/workflows/firmware.yml.
set -e
cd "$(dirname "$0")"
SK=../../SpoolDry
for f in $SK/src/hal/Hardware.cpp $SK/src/hal/BleLink.cpp $SK/src/core/Protocol.cpp $SK/src/core/DryerController.cpp; do
  g++ -std=gnu++17 -fsyntax-only -Wall -Wextra -Werror -Imocks "$f"
done
cp $SK/SpoolDry.ino /tmp/spooldry_ino_check.cpp
g++ -std=gnu++17 -fsyntax-only -Wall -Wextra -Werror -Imocks -I$SK /tmp/spooldry_ino_check.cpp
echo "compile_check: OK"
