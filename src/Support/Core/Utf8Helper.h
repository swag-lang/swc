#pragma once

SWC_BEGIN_NAMESPACE();

class LangSpec;

namespace Utf8Helper
{
    Runtime::String                                runtimeStringFromUtf8(const Utf8& value);
    std::tuple<const char8_t*, char32_t, uint32_t> decodeOneChar(const char8_t* cur, const char8_t* end);
    const char8_t*                                 decodeOneChar(const char8_t* cur, const char8_t* end, char32_t& c, uint32_t& offset);
    uint32_t                                       countChars(std::string_view str);
    Utf8                                           substrChars(std::string_view s, uint32_t charStart, uint32_t charEnd);

    Utf8 toNiceSize(size_t size);
    Utf8 toNiceBigNumber(std::size_t number);
    Utf8 toNiceTime(double seconds);
    Utf8 toLowerSnake(std::string_view s);
    bool isHexToken(std::string_view token);
    bool parseUInt(const LangSpec& langSpec, std::string_view s, size_t& p, int& out) noexcept;
    bool parseSignedOrAbs(const LangSpec& langSpec, std::string_view s, size_t& p, int& value, bool& hasSign) noexcept;

    std::string_view trimLeft(std::string_view s);
    std::string_view trimRight(std::string_view s);
    std::string_view trim(std::string_view s);
    bool             startsWith(std::string_view s, std::string_view pfx, bool matchCase = false);
    Utf8             addArticleAAn(std::string_view s);
}

SWC_END_NAMESPACE();
