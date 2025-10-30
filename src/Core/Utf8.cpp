#include "pch.h"
#include "Utf8.h"

SWC_BEGIN_NAMESPACE()

void Utf8::trimStart()
{
    erase(begin(), std::ranges::find_if(begin(), end(), [](unsigned char ch) { return !std::isspace(ch); }));
}

void Utf8::trimEnd()
{
    erase(std::ranges::find_if(rbegin(), rend(), [](unsigned char ch) { return !std::isspace(ch); }).base(), end());
}

void Utf8::trim()
{
    trimStart();
    trimEnd();
}

void Utf8::clean()
{
    std::ranges::replace_if(*this, [](unsigned char ch) { return ch < 0x20 || ch == 0x7F; }, ' ');
}

void Utf8::makeLower()
{
    std::ranges::transform(*this, begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
}

void Utf8::makeUpper()
{
    std::ranges::transform(*this, begin(), [](unsigned char ch) { return static_cast<char>(std::toupper(ch)); });
}

void Utf8::replaceOutsideQuotes(std::string_view from, std::string_view to, bool loopReplace)
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
            char ch = input[i];

            // Toggle quote states
            if (ch == '\'' && !inDoubleQuote)
            {
                inSingleQuote = !inSingleQuote;
                result += ch;
                ++i;
                continue;
            }
            else if (ch == '"' && !inSingleQuote)
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
    Utf8 next = doReplace(current);

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

SWC_END_NAMESPACE()
