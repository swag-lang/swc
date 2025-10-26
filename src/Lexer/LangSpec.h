#pragma once

SWC_BEGIN_NAMESPACE();

enum class TokenId : uint16_t;

enum class CharFlagsEnum : uint32_t
{
    Blank           = 1 << 0,
    Digit           = 1 << 1,
    Letter          = 1 << 2,
    Ascii           = 1 << 3,
    HexNumber       = 1 << 4,
    BinNumber       = 1 << 5,
    NumberSep       = 1 << 6,
    IdentifierStart = 1 << 7,
    IdentifierPart  = 1 << 8,
    Escape          = 1 << 9,
    Option          = 1 << 10,
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
    bool isOption(uint8_t c) const { return charFlags_[c].has(CharFlagsEnum::Option); }

    static TokenId keyword(std::string_view name);

    static constexpr std::string_view VERIFY_COMMENT_OPTION   = "swc-option";
    static constexpr std::string_view VERIFY_COMMENT_EXPECTED = "swc-expected-";

private:
    CharFlags charFlags_[256];
};

SWC_END_NAMESPACE();
