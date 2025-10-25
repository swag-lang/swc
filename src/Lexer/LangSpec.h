#pragma once

SWC_BEGIN_NAMESPACE();

enum class TokenId : uint16_t;

enum class CharFlagsEnum : uint32_t
{
    Blank           = 0x00000001,
    Digit           = 0x00000002,
    Letter          = 0x00000004,
    Ascii           = 0x00000008,
    HexNumber       = 0x00000010,
    BinNumber       = 0x00000020,
    NumberSep       = 0x00000040,
    IdentifierStart = 0x00000080,
    IdentifierPart  = 0x00000100,
    Escape          = 0x00000200,
};

using CharFlags = Flags<CharFlagsEnum>;

class LangSpec
{
    friend class Global;
    void setup();

public:
    bool isBlank(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Blank); }
    bool isBlank(const uint8_t* buffer, const uint8_t* end, uint32_t& offset) const;
    bool isDigit(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Digit); }
    bool isLetter(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Letter); }
    bool isAscii(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Ascii); }
    bool isHexNumber(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::HexNumber); }
    bool isBinNumber(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::BinNumber); }
    bool isNumberSep(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::NumberSep); }
    bool isIdentifierStart(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::IdentifierStart); }
    bool isIdentifierPart(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::IdentifierPart); }
    bool isEscape(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Escape); }

    static TokenId keyword(std::string_view name);

private:
    CharFlags charFlags_[256];
};

SWC_END_NAMESPACE();
