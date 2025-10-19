#include "pch.h"
#include "Utf8.h"

// Returns {next_ptr, code_point, bytes_consumed}.
// On error: {nullptr, 0, 0}.
std::tuple<const char*, uint32_t, unsigned> Utf8::decode(const char* p, const char* end)
{
    const auto u = reinterpret_cast<const uint8_t*>(p);
    const auto e = reinterpret_cast<const uint8_t*>(end);

    if (u >= e)
        return {nullptr, 0, 0};

    const uint8_t b0 = *u;

    // Fast ASCII path
    if (b0 < 0x80)
    {
        return {reinterpret_cast<const char*>(u + 1), static_cast<uint32_t>(b0), 1};
    }

    // 2-byte: 110xxxxx 10xxxxxx (U+0080..U+07FF), no overlongs (b0 >= 0xC2)
    if ((b0 & 0xE0) == 0xC0)
    {
        if (e - u < 2)
            return {nullptr, 0, 0};
        const uint8_t b1 = u[1];
        if (b0 < 0xC2 || (b1 & 0xC0) != 0x80)
            return {nullptr, 0, 0};
        uint32_t wc = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
        return {reinterpret_cast<const char*>(u + 2), wc, 2};
    }

    // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx (U+0800..U+FFFF excluding surrogates)
    if ((b0 & 0xF0) == 0xE0)
    {
        if (e - u < 3)
            return {nullptr, 0, 0};
        const uint8_t b1 = u[1];
        const uint8_t b2 = u[2];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80)
            return {nullptr, 0, 0};
        if (b0 == 0xE0 && b1 < 0xA0)
            return {nullptr, 0, 0}; // overlong
        if (b0 == 0xED && b1 >= 0xA0)
            return {nullptr, 0, 0}; // surrogates
        uint32_t wc = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
        return {reinterpret_cast<const char*>(u + 3), wc, 3};
    }

    // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx (U+10000..U+10FFFF)
    if ((b0 & 0xF8) == 0xF0)
    {
        if (e - u < 4)
            return {nullptr, 0, 0};
        const uint8_t b1 = u[1];
        const uint8_t b2 = u[2];
        const uint8_t b3 = u[3];
        if ((b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80)
            return {nullptr, 0, 0};
        if (b0 == 0xF0 && b1 < 0x90)
            return {nullptr, 0, 0}; // overlong
        if (b0 > 0xF4 || (b0 == 0xF4 && b1 > 0x8F))
            return {nullptr, 0, 0}; // > U+10FFFF
        uint32_t wc = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) |
                      ((b2 & 0x3F) << 6) | (b3 & 0x3F);
        return {reinterpret_cast<const char*>(u + 4), wc, 4};
    }

    // Invalid lead byte
    return {nullptr, 0, 0};
}
