#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
"${CC:-cc}" -std=c11 -Wall -Wextra -Werror -Wpedantic -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -Iinclude src/platform_protocol.c tests/test_protocol.c -lm -o build/test_protocol
./build/test_protocol
