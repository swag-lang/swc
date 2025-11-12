#include "pch.h"
#include "Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()

// Returns {next_ptr, code_point, bytes_consumed}.
// On error: {nullptr, 0, 0}.
std::tuple<const uint8_t*, uint32_t, uint32_t> Utf8Helper::decodeOneChar(const uint8_t* cur, const uint8_t* end)
{
    const auto u = cur;
    const auto e = end;

    if (u >= e)
        return {nullptr, 0, 0};

    const uint8_t b0 = *u;

    // Fast ASCII path
    if (b0 < 0x80)
    {
        return {u + 1, static_cast<uint32_t>(b0), 1};
    }

    // 2-byte: 110xxxxx 10xxxxxx (U+0080..U+07FF), no overlong (b0 >= 0xC2)
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

const uint8_t* Utf8Helper::decodeOneChar(const uint8_t* cur, const uint8_t* end, uint32_t& c, uint32_t& offset)
{
    const auto result = decodeOneChar(cur, end);
    c                 = std::get<1>(result);
    offset            = std::get<2>(result);
    return std::get<0>(result);
}

uint32_t Utf8Helper::countChars(std::string_view str)
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

Utf8 Utf8Helper::toNiceSize(std::size_t size)
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

Utf8 Utf8Helper::toNiceBigNumber(std::size_t number)
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

Utf8 Utf8Helper::toNiceTime(double seconds)
{
    static constexpr double MICROSECOND = 0.000001;
    static constexpr double MILLISECOND = 0.001;
    static constexpr double MINUTE      = 60.0;

    if (seconds == 0.0)
        return "0s";

    // Microseconds (< 1ms)
    if (seconds < MILLISECOND)
    {
        auto us = static_cast<size_t>(seconds / MICROSECOND);
        return std::format("{} µs", us);
    }

    // Milliseconds (< 1s)
    if (seconds < 1.0)
    {
        auto ms = static_cast<size_t>(seconds / MILLISECOND);
        return std::format("{} ms", ms);
    }

    // Seconds only (< 1min)
    if (seconds < MINUTE)
    {
        auto wholeSeconds = static_cast<size_t>(seconds);
        auto ms           = static_cast<size_t>((seconds - static_cast<double>(wholeSeconds)) / MILLISECOND);
        return std::format("{} s {} ms", wholeSeconds, ms);
    }

    // Minutes and seconds (>= 1 min)
    auto minutes          = static_cast<size_t>(seconds / MINUTE);
    auto remainingSeconds = static_cast<size_t>(seconds - (static_cast<double>(minutes) * MINUTE));
    return std::format("{} min {} s", minutes, remainingSeconds);
}

// whitespace helpers
std::string_view Utf8Helper::trimLeft(std::string_view s)
{
    while (!s.empty() && std::isspace(s.front()))
        s.remove_prefix(1);
    return s;
}

std::string_view Utf8Helper::trimRight(std::string_view s)
{
    while (!s.empty() && std::isspace(s.back()))
        s.remove_suffix(1);
    return s;
}

std::string_view Utf8Helper::trim(std::string_view s)
{
    return trimRight(trimLeft(s));
}

// ASCII-case-insensitive starts-with
bool Utf8Helper::startsWith(std::string_view s, std::string_view pfx, bool matchCase)
{
    if (s.size() < pfx.size())
        return false;
    for (size_t i = 0; i < pfx.size(); ++i)
    {
        char a = s[i], b = pfx[i];

        if (!matchCase)
        {
            if ('A' <= a && a <= 'Z')
                a = static_cast<char>(a - 'A' + 'a');
            if ('A' <= b && b <= 'Z')
                b = static_cast<char>(b - 'A' + 'a');
        }

        if (a != b)
            return false;
    }
    return true;
}

// Return a substring of 's' spanning [charStart, charEnd] in *character* (code point) indices, 1-based inclusive.
// Falls back to byte slicing when ASCII; otherwise walks UTF-8 safely.
Utf8 Utf8Helper::substrChars(std::string_view s, uint32_t charStart, uint32_t charEnd)
{
    if (charStart > charEnd || s.empty())
        return {};

    // Fast path for likely-ASCII: if sizes match, assume 1 byte per char.
    const bool asciiLikely = countChars(s) == s.size();
    if (asciiLikely)
    {
        const uint32_t start0 = (charStart ? charStart : 1) - 1;
        const uint32_t len    = charEnd - (charStart ? charStart : 1) + 1;
        const uint32_t ssz    = static_cast<uint32_t>(s.size());
        if (start0 >= ssz)
            return {};
        const uint32_t safeLen = std::min<uint32_t>(len, ssz - start0);
        return Utf8{s.substr(start0, safeLen)};
    }

    // UTF-8 safe path
    uint32_t cpIndex   = 1;
    size_t   startByte = Utf8::npos;
    size_t   endByte   = Utf8::npos;

    for (size_t i = 0; i < s.size();)
    {
        const unsigned char c   = static_cast<unsigned char>(s[i]);
        size_t              adv = 1;
        if ((c & 0x80) == 0x00)
            adv = 1;
        else if ((c & 0xE0) == 0xC0)
            adv = 2;
        else if ((c & 0xF0) == 0xE0)
            adv = 3;
        else if ((c & 0xF8) == 0xF0)
            adv = 4;

        if (cpIndex == charStart)
            startByte = i;
        if (cpIndex == charEnd + 1)
        {
            endByte = i;
            break;
        }

        i += adv;
        ++cpIndex;
    }
    if (startByte == Utf8::npos)
        return {};
    if (endByte == Utf8::npos)
        endByte = s.size();
    return Utf8{s.substr(startByte, endByte - startByte)};
}

uint32_t Utf8Helper::countLeadingBlanks(const TaskContext& ctx, std::string_view s, uint32_t upto)
{
    // Count spaces and tabs only; extend if you want more Unicode categories.
    uint32_t       i = 0;
    const uint32_t n = std::min<uint32_t>(static_cast<uint32_t>(s.length()), upto);
    while (i < n)
    {
        if (!ctx.global().langSpec().isBlank(s[i]))
            break;
        ++i;
    }
    return i;
}

SWC_END_NAMESPACE()
