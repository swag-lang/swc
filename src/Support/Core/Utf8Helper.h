#pragma once

SWC_BEGIN_NAMESPACE();

class LangSpec;

namespace Utf8Helper
{
    enum class TruncateMode : uint8_t
    {
        End,
        Start,
        Middle,
    };

    struct TruncateOptions
    {
        uint32_t         maxChars       = 0;
        TruncateMode     mode           = TruncateMode::End;
        uint32_t         keepLeftChars  = 0;
        uint32_t         keepRightChars = 0;
        std::string_view ellipsis       = "...";
        bool             forceEllipsis  = false;
    };

    Runtime::String                                runtimeStringFromUtf8(const Utf8& value);
    std::tuple<const char8_t*, char32_t, uint32_t> decodeOneChar(const char8_t* cur, const char8_t* end);
    const char8_t*                                 decodeOneChar(const char8_t* cur, const char8_t* end, char32_t& c, uint32_t& offset);
    uint32_t                                       countChars(std::string_view str);
    Utf8                                           substrChars(std::string_view s, uint32_t charStart, uint32_t charEnd);
    Utf8                                           truncate(std::string_view s, const TruncateOptions& options);

    Utf8 toNiceSize(size_t size);
    Utf8 toNiceBigNumber(std::size_t number);
    Utf8 toNiceTime(double seconds);
    Utf8 toLowerSnake(std::string_view s);
    bool isHexToken(std::string_view token);
    bool parseUInt(const LangSpec& langSpec, std::string_view s, size_t& p, int& out) noexcept;
    bool parseSignedOrAbs(const LangSpec& langSpec, std::string_view s, size_t& p, int& value, bool& hasSign) noexcept;

    size_t levenshtein(std::string_view a, std::string_view b);

    std::string_view trimLeft(std::string_view s);
    std::string_view trimRight(std::string_view s);
    std::string_view trim(std::string_view s);
    bool             startsWith(std::string_view s, std::string_view pfx, bool matchCase = false);
    Utf8             addArticleAAn(std::string_view s);
    Utf8             countWithLabel(size_t value, std::string_view singular, const char* plural = nullptr);
}

SWC_END_NAMESPACE();
