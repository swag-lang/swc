// ReSharper disable CppInconsistentNaming
#include "pch.h"
#include "Support/Core/Utf8.h"
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // <cctype> expects unsigned-char values; using signed chars here is undefined for non-ASCII bytes.
    bool isWhitespaceByte(const char8_t ch)
    {
        return std::isspace(static_cast<unsigned char>(ch)) != 0;
    }

    bool isControlByte(const char8_t ch)
    {
        return ch < 0x20 || ch == 0x7F;
    }

    char toLowerAsciiByte(const char8_t ch)
    {
        return static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }

    char toUpperAsciiByte(const char8_t ch)
    {
        return static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));
    }

    Utf8 replaceOutsideQuotes(std::string_view input, std::string_view from, std::string_view to)
    {
        Utf8 result;
        result.reserve(input.size());

        bool inSingleQuote = false;
        bool inDoubleQuote = false;

        for (size_t i = 0; i < input.size();)
        {
            const char ch = input[i];

            // Toggle quote states
            if (ch == '\'' && !inDoubleQuote)
            {
                inSingleQuote = !inSingleQuote;
                result += ch;
                ++i;
                continue;
            }

            if (ch == '"' && !inSingleQuote)
            {
                inDoubleQuote = !inDoubleQuote;
                result += ch;
                ++i;
                continue;
            }

            // If not inside quotes, check for substring match
            if (!inSingleQuote && !inDoubleQuote && input.compare(i, from.size(), from) == 0)
            {
                result += to;
                i += from.size();
            }
            else
            {
                result += ch;
                ++i;
            }
        }

        return result;
    }
}

Utf8::Utf8(const fs::path& path) :
    std::string(path.generic_string())
{
}

Utf8::Utf8(const Runtime::String& value) :
    std::string(value.ptr && value.length ? std::string_view(value.ptr, value.length) : std::string_view{})
{
}

void Utf8::trim_start()
{
    erase(begin(), std::ranges::find_if_not(begin(), end(), isWhitespaceByte));
}

void Utf8::trim_end()
{
    erase(std::ranges::find_if_not(rbegin(), rend(), isWhitespaceByte).base(), end());
}

void Utf8::trim()
{
    trim_start();
    trim_end();
}

void Utf8::clean()
{
    std::ranges::replace_if(*this, isControlByte, ' ');
}

void Utf8::make_lower()
{
    std::ranges::transform(*this, begin(), toLowerAsciiByte);
}

void Utf8::make_upper()
{
    std::ranges::transform(*this, begin(), toUpperAsciiByte);
}

void Utf8::replace_loop(std::string_view from, std::string_view to, bool loopReplace)
{
    if (from.empty())
        return;

    Utf8 current = *this;
    Utf8 next    = replaceOutsideQuotes(current, from, to);

    // Loop until no more changes if requested
    if (loopReplace)
    {
        while (next != current)
        {
            current.swap(next);
            next = replaceOutsideQuotes(current, from, to);
        }
    }

    *this = next;
}

void Utf8::push_back_uni(char32_t cp)
{
    // Replace invalid values (surrogates or > U+10FFFF) with U+FFFD
    if ((cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF)
    {
        // U+FFFD in UTF-8
        this->append("\xEF\xBF\xBD");
        return;
    }

    // Reserve up to 4 extra bytes (max UTF-8 length)
    this->reserve(this->size() + 4);

    if (cp <= 0x7F)
    {
        this->push_back(static_cast<char>(cp));
    }
    else if (cp <= 0x7FF)
    {
        this->push_back(static_cast<char>(0xC0 | (cp >> 6)));
        this->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
    else if (cp <= 0xFFFF)
    {
        this->push_back(static_cast<char>(0xE0 | (cp >> 12)));
        this->push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        this->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
    else
    {
        this->push_back(static_cast<char>(0xF0 | (cp >> 18)));
        this->push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        this->push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        this->push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

SWC_END_NAMESPACE();
