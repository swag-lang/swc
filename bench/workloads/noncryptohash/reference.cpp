#include <city.h>
#include <MurmurHash2.h>

#include <charconv>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <time.h>
#include <vector>

#ifndef CITYHASH_REVISION
#define CITYHASH_REVISION "unknown"
#endif
#ifndef SMHASHER_REVISION
#define SMHASHER_REVISION "unknown"
#endif

using Hash = uint64_t (*)(const char *, int);

uint64_t city(const char *data, int size) { return CityHash32(data, size); }
uint64_t murmur(const char *data, int size) { return MurmurHash64A(data, size, 0); }

int64_t ticks(clockid_t clock)
{
    timespec stamp;
    if (clock_gettime(clock, &stamp) != 0)
        std::exit(2);
    return stamp.tv_sec * 1000000000LL + stamp.tv_nsec;
}

unsigned long long number(const char *value)
{
    unsigned long long result;
    const char *end = value + std::strlen(value);
    const auto parsed = std::from_chars(value, end, result);
    if (parsed.ec != std::errc{} || parsed.ptr != end)
        std::exit(2);
    return result;
}

int main(int argc, char **argv)
{
    if (argc == 2 && std::strcmp(argv[1], "--version") == 0)
    {
        std::cout << "CityHash " CITYHASH_REVISION ", SMHasher " SMHASHER_REVISION "\n";
        return 0;
    }
    if (argc != 6)
        return 2;
    const bool is_city = std::strcmp(argv[1], "cityhash32") == 0;
    if (!is_city && std::strcmp(argv[1], "murmur64a") != 0)
        return 2;

    const auto iterations = number(argv[4]);
    const auto offset = number(argv[5]);
    if (!iterations)
        return 2;
    std::ifstream input(argv[2], std::ios::binary | std::ios::ate);
    const auto length = input.tellg();
    if (length < 0 || length > INT_MAX || offset > static_cast<unsigned long long>(length))
        return 2;
    std::vector<char> storage(static_cast<size_t>(length) + 1);
    input.seekg(0);
    if (!input.read(storage.data(), length))
        return 2;
    const auto *data = storage.data() + offset;
    const int size = static_cast<int>(length) - static_cast<int>(offset);
    if (is_city && size < 5)
        return 2; // Swag's unsigned-byte CityHash32 variant differs from upstream below five bytes.
    const Hash compute = is_city ? city : murmur;
    uint64_t result = compute(data, size);

    const auto wall_start = ticks(CLOCK_MONOTONIC);
    const auto cpu_start = ticks(CLOCK_PROCESS_CPUTIME_ID);
    for (unsigned long long i = 0; i < iterations; ++i)
        result = compute(data, size);
    const auto cpu_elapsed = ticks(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const auto wall_elapsed = ticks(CLOCK_MONOTONIC) - wall_start;

    std::ofstream output(argv[3], std::ios::binary);
    const int output_size = is_city ? 4 : 8;
    for (int i = 0; i < output_size; ++i)
        output.put(static_cast<char>(result >> (i * 8)));
    if (!output)
        return 2;
    std::cout << wall_elapsed << ' ' << cpu_elapsed << " 1000000000\n";
}
