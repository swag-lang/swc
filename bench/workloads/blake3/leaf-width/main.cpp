#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <vector>

extern "C" {
#include "blake3_impl.h"
void sse41_kernel4(const std::uint8_t*, std::size_t, std::uint64_t, const std::uint32_t*, std::uint8_t, std::uint8_t*);
void avx2_kernel4(const std::uint8_t*, std::size_t, std::uint64_t, const std::uint32_t*, std::uint8_t, std::uint8_t*);
void avx2_kernel8(const std::uint8_t*, std::size_t, std::uint64_t, const std::uint32_t*, std::uint8_t, std::uint8_t*);
}

static std::uint64_t now(clockid_t clock)
{
    timespec time{};
    if (clock_gettime(clock, &time)) std::abort();
    return time.tv_sec * UINT64_C(1000000000) + time.tv_nsec;
}

int main(int argc, char** argv)
{
    if (argc != 6) return 2;
    const auto count = std::strtoull(argv[2], nullptr, 10);
    const auto repeats = std::strtoull(argv[3], nullptr, 10);
    const auto offset = std::strtoull(argv[4], nullptr, 10);
    const auto flag = static_cast<std::uint8_t>(std::strtoul(argv[5], nullptr, 10));
    if (!repeats || !count || count % 8 || (flag != 0 && flag != KEYED_HASH)) return 2;
    constexpr std::array<std::uint32_t, 8> key = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    };
    const std::array<std::uint32_t, 8> keyed = {
        0xd512c859, 0x889f7cb9, 0x2deb028b, 0x3c84e5f0, 0x2095a599, 0x7631ee5e, 0xcb5a69d9, 0xc1a93370,
    };
    const auto* state = flag ? keyed.data() : key.data();
    constexpr auto counter = (UINT64_C(1) << 32) - 3;
    std::vector<std::uint8_t> bytes(count * 1024 + offset);
    for (std::size_t i = 0; i < count * 1024; ++i) bytes[i + offset] = i % 251;
    const auto* input = bytes.data() + offset;
    std::vector<std::uint8_t> output(count * BLAKE3_OUT_LEN), reference(count * BLAKE3_OUT_LEN);
    std::vector<const std::uint8_t*> starts(count);
    for (std::size_t i = 0; i < count; ++i) starts[i] = input + i * 1024;
    blake3_hash_many(starts.data(), count, 16, state, counter, true, flag, CHUNK_START, CHUNK_END, reference.data());

    using Kernel = decltype(&sse41_kernel4);
    Kernel kernel = nullptr;
    if (std::strcmp(argv[1], "sse4") == 0) kernel = &sse41_kernel4;
    if (std::strcmp(argv[1], "avx4") == 0) kernel = &avx2_kernel4;
    if (std::strcmp(argv[1], "avx8") == 0) kernel = &avx2_kernel8;
    if (std::strcmp(argv[1], "official") != 0 && !kernel) return 2;
    auto run = [&] {
        if (kernel)
            kernel(input, count, counter, state, flag, output.data());
        else
            blake3_hash_many(starts.data(), count, 16, state, counter, true, flag, CHUNK_START, CHUNK_END, output.data());
    };
    run();
    if (output != reference) return 3;
    const auto wall = now(CLOCK_MONOTONIC);
    const auto cpu = now(CLOCK_PROCESS_CPUTIME_ID);
    for (std::size_t repeat = 0; repeat < repeats; ++repeat) run();
    const auto elapsed = now(CLOCK_PROCESS_CPUTIME_ID) - cpu;
    const auto elapsed_wall = now(CLOCK_MONOTONIC) - wall;
    if (output != reference) return 3;
    std::printf("%llu %llu %zu\n", (unsigned long long)elapsed, (unsigned long long)elapsed_wall, blake3_simd_degree());
}
