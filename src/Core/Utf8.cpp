#include "pch.h"
#include "Utf8.h"

SWC_BEGIN_NAMESPACE();

void Utf8::trimStart()
{
    auto isNotSpace = [](unsigned char ch) {
        return !std::isspace(ch);
    };

    erase(begin(), std::ranges::find_if(begin(), end(), isNotSpace));
}

void Utf8::trimEnd()
{
    auto isNotSpace = [](unsigned char ch) {
        return !std::isspace(ch);
    };

    erase(std::ranges::find_if(rbegin(), rend(), isNotSpace).base(), end());
}

void Utf8::trim()
{
    trimStart();
    trimEnd();
}

SWC_END_NAMESPACE();
