#pragma once
#include "Core/Flags.h"

using CharFlags                 = Flags<uint32_t>;
constexpr CharFlags CHAR_BLANK  = 0x00000001;
constexpr CharFlags CHAR_DIGIT  = 0x00000002;
constexpr CharFlags CHAR_LETTER = 0x00000004;
constexpr CharFlags CHAR_ASCII  = 0x00000008;

class LangSpec
{
public:
    LangSpec();

    bool isBlank(char c) const { return charFlags_[static_cast<uint8_t>(c)].has(CHAR_BLANK); }
    bool isDigit(char c) const { return charFlags_[static_cast<uint8_t>(c)].has(CHAR_DIGIT); }
    bool isLetter(char c) const { return charFlags_[static_cast<uint8_t>(c)].has(CHAR_LETTER); }
    bool isAscii(char c) const { return charFlags_[static_cast<uint8_t>(c)].has(CHAR_ASCII); }

private:
    CharFlags charFlags_[256];

    void initCharFlags();
};
