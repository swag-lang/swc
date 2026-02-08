#pragma once
#include "Support/Core/Flags.h"
#include "Support/Core/StringMap.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct AstEnumDecl;

enum class TokenId : uint16_t;
enum class SpecialFuncKind : uint8_t;

enum class CharFlagsE : uint32_t
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
    Eol             = 1 << 11,
};
using CharFlags = EnumFlags<CharFlagsE>;

class LangSpec
{
    friend class Global;

public:
    bool isBlank(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Blank); }
    bool isWhiteSpace(uint32_t c) const { return c < 256 && charFlags_[c].hasAny({CharFlagsE::Blank, CharFlagsE::Eol}); }
    bool isEol(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Eol); }
    bool isDigit(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Digit); }
    bool isLetter(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Letter); }
    bool isAscii(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Ascii); }
    bool isHexNumber(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::HexNumber); }
    bool isBinNumber(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::BinNumber); }
    bool isNumberSep(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::NumberSep); }
    bool isIdentifierStart(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::IdentifierStart); }
    bool isIdentifierPart(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::IdentifierPart); }
    bool isEscape(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Escape); }
    bool isOption(uint32_t c) const { return c < 256 && charFlags_[c].has(CharFlagsE::Option); }

    TokenId keyword(std::string_view name, uint32_t hash) const;
    TokenId keyword(std::string_view name) const;

    static constexpr std::string_view VERIFY_COMMENT_OPTION   = "swc-option";
    static constexpr std::string_view VERIFY_COMMENT_EXPECTED = "swc-expected-";

    static bool isReservedNamespace(std::string_view ns);
    static bool isSpecialFunctionName(std::string_view name);
    static bool isOpVisitName(std::string_view name);
    static bool matchSpecialFunction(std::string_view name, SpecialFuncKind& outKind);

private:
    CharFlags                                     charFlags_[256];
    StringMap<TokenId>                            keywordMap_;
    std::unordered_map<TokenId, std::string_view> keywordIdMap_;

    void setup();
    void setupKeywords();
    void setupCharFlags();
};

SWC_END_NAMESPACE();
