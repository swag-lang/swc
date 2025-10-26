#include "pch.h"
#include "Utf8.h"

SWC_BEGIN_NAMESPACE();

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

SWC_END_NAMESPACE();
