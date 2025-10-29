#pragma once
#include "Core/Flags.h"
#include "Core/StringMap.h"
#include "Lexer/KeywordTable.h"

SWC_BEGIN_NAMESPACE()

enum class TokenId : uint16_t;

enum class CharFlags : uint32_t
{
    Zero            = 0,
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
SWC_ENABLE_BITMASK(CharFlags);

class LangSpec
{
    friend class Global;
    void setup();

public:
    bool isBlank(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Blank); }
    bool isBlank(const uint8_t* buffer, const uint8_t* end, uint32_t& offset) const;
    bool isDigit(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Digit); }
    bool isLetter(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Letter); }
    bool isAscii(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Ascii); }
    bool isHexNumber(uint8_t c) const { return has_any(charFlags_[c], CharFlags::HexNumber); }
    bool isBinNumber(uint8_t c) const { return has_any(charFlags_[c], CharFlags::BinNumber); }
    bool isNumberSep(uint8_t c) const { return has_any(charFlags_[c], CharFlags::NumberSep); }
    bool isIdentifierStart(uint8_t c) const { return has_any(charFlags_[c], CharFlags::IdentifierStart); }
    bool isIdentifierPart(uint8_t c) const { return has_any(charFlags_[c], CharFlags::IdentifierPart); }
    bool isEscape(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Escape); }
    bool isOption(uint8_t c) const { return has_any(charFlags_[c], CharFlags::Option); }

    TokenId keyword(std::string_view name, uint64_t hash);

    static constexpr std::string_view VERIFY_COMMENT_OPTION   = "swc-option";
    static constexpr std::string_view VERIFY_COMMENT_EXPECTED = "swc-expected-";

private:
    CharFlags                                     charFlags_[256];
    StringMap<TokenId>                            keywordMap_;
    std::unordered_map<TokenId, std::string_view> keywordIdMap_;

    void setupKeywords();
    void setupCharFlags();
};

SWC_END_NAMESPACE()
