// ReSharper disable CppInconsistentNaming
#include "pch.h"
#include "Utf8.h"

SWC_BEGIN_NAMESPACE()

void Utf8::trim_start()
{
    erase(begin(), std::ranges::find_if(begin(), end(), [](char8_t ch) { return !std::isspace(ch); }));
}

void Utf8::trim_end()
{
    erase(std::ranges::find_if(rbegin(), rend(), [](char8_t ch) { return !std::isspace(ch); }).base(), end());
}

void Utf8::trim()
{
    trim_start();
    trim_end();
}

void Utf8::clean()
{
    std::ranges::replace_if(*this, [](char8_t ch) { return ch < 0x20 || ch == 0x7F; }, ' ');
}

void Utf8::make_lower()
{
    std::ranges::transform(*this, begin(), [](char8_t ch) { return static_cast<char>(std::tolower(ch)); });
}

void Utf8::make_upper()
{
    std::ranges::transform(*this, begin(), [](char8_t ch) { return static_cast<char>(std::toupper(ch)); });
}

void Utf8::replace_loop(std::string_view from, std::string_view to, bool loopReplace)
{
    if (from.empty())
        return;

    auto doReplace = [&](std::string_view input) -> Utf8 {
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
    };

    Utf8 current = *this;
    Utf8 next    = doReplace(current);

    // Loop until no more changes if requested
    if (loopReplace)
    {
        while (next != current)
        {
            current.swap(next);
            next = doReplace(current);
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

SWC_END_NAMESPACE()
