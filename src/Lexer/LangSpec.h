#pragma once
#include "Core/Flags.h"

using CharFlags                     = Flags<uint8_t>;
constexpr CharFlags CHAR_BLANK      = 0x00000001;
constexpr CharFlags CHAR_DIGIT      = 0x00000002;
constexpr CharFlags CHAR_LETTER     = 0x00000004;
constexpr CharFlags CHAR_ASCII      = 0x00000008;
constexpr CharFlags CHAR_HEX_NUMBER = 0x00000010;
constexpr CharFlags CHAR_BIN_NUMBER = 0x00000020;
constexpr CharFlags CHAR_NUMBER_SEP = 0x00000040;

class LangSpec
{
public:
    LangSpec();

    bool isBlank(uint8_t c) const { return charFlags_[c].has(CHAR_BLANK); }
    bool isBlank(const uint8_t* buffer, const uint8_t* end, uint32_t& offset) const;
    bool isDigit(uint8_t c) const { return charFlags_[c].has(CHAR_DIGIT); }
    bool isLetter(uint8_t c) const { return charFlags_[c].has(CHAR_LETTER); }
    bool isAscii(uint8_t c) const { return charFlags_[c].has(CHAR_ASCII); }
    bool isHexNumber(uint8_t c) const { return charFlags_[c].has(CHAR_HEX_NUMBER); }
    bool isBinNumber(uint8_t c) const { return charFlags_[c].has(CHAR_BIN_NUMBER); }
    bool isNumberSep(uint8_t c) const { return charFlags_[c].has(CHAR_NUMBER_SEP); }

private:
    CharFlags charFlags_[256];

    void initCharFlags();
};
