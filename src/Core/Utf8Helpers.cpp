#include "pch.h"
#include "Utf8Helpers.h"

// Returns {next_ptr, code_point, bytes_consumed}.
// On error: {nullptr, 0, 0}.
std::tuple<const uint8_t*, uint32_t, uint32_t> Utf8Helpers::decodeOneChar(const uint8_t* p, const uint8_t* end)
{
    const auto u = p;
    const auto e = end;

    if (u >= e)
        return {nullptr, 0, 0};

    const uint8_t b0 = *u;

    // Fast ASCII path
    if (b0 < 0x80)
    {
        return {u + 1, static_cast<uint32_t>(b0), 1};
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
        return {u + 2, wc, 2};
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
        return {u + 3, wc, 3};
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
        uint32_t wc = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
        return {u + 4, wc, 4};
    }

    // Invalid lead byte
    return {nullptr, 0, 0};
}

uint32_t Utf8Helpers::countChars(std::string_view str)
{
    int result = 0;
    for (size_t i = 0; i < str.size(); i++)
    {
        const auto [ptr, wc, bytes] = decodeOneChar(reinterpret_cast<const uint8_t*>(str.data() + i), reinterpret_cast<const uint8_t*>(str.data() + str.size()));
        if (ptr)
            i += bytes - 1;
        result++;
    }

    return result;
}

Utf8 Utf8Helpers::toNiceSize(std::size_t size)
{
    static constexpr size_t KB = 1024;
    static constexpr size_t MB = KB * 1024;
    static constexpr size_t GB = MB * 1024;
    static constexpr size_t TB = GB * 1024;

    if (size == 1)
        return "1 byte";
    if (size < 1024)
        return std::format("{} bytes", size);
    if (size < MB)
        return std::format("{:.1f} KB", static_cast<double>(size) / KB);
    if (size < GB)
        return std::format("{:.1f} MB", static_cast<double>(size) / MB);
    if (size < TB)
        return std::format("{:.1f} GB", static_cast<double>(size) / GB);
    return std::format("{:.1f} TB", static_cast<double>(size) / TB);
}

Utf8 Utf8Helpers::toNiceBigNumber(std::size_t number)
{
    auto str = std::format("{}", number);

    // Insert separators from right to left
    int count = 0;
    for (auto it = str.rbegin(); it != str.rend(); ++it)
    {
        if (++count == 4)
        {
            str.insert(it.base(), '_');
            count = 1;
        }
    }

    return str;
}
