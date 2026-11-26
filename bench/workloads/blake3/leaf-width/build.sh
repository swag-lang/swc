#!/usr/bin/env bash
set -euo pipefail
work=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
upstream=$(realpath "$1")
build=$(realpath -m "$2")
mkdir -p "$build"
cd "$build"
c++ -Wall -Wextra -Werror -O3 -msse4.1 -mno-avx -DLANES=4 -DKERNEL=sse41_kernel4 -c "$work/kernel.cpp" -o sse4.o
c++ -Wall -Wextra -Werror -O3 -mavx2 -mno-avx512f -DLANES=4 -DKERNEL=avx2_kernel4 -c "$work/kernel.cpp" -o avx4.o
c++ -Wall -Wextra -Werror -O3 -mavx2 -mno-avx512f -DLANES=8 -DKERNEL=avx2_kernel8 -c "$work/kernel.cpp" -o avx8.o
cc -O3 -I"$upstream" -c "$upstream/blake3.c" "$upstream/blake3_dispatch.c" "$upstream/blake3_portable.c" \
    "$upstream/blake3_sse2_x86-64_unix.S" "$upstream/blake3_sse41_x86-64_unix.S" \
    "$upstream/blake3_avx2_x86-64_unix.S" "$upstream/blake3_avx512_x86-64_unix.S"
c++ -Wall -Wextra -Werror -O3 -I"$upstream" "$work/main.cpp" sse4.o avx4.o avx8.o \
    blake3.o blake3_dispatch.o blake3_portable.o blake3_sse2_x86-64_unix.o blake3_sse41_x86-64_unix.o \
    blake3_avx2_x86-64_unix.o blake3_avx512_x86-64_unix.o -o blake3-width
