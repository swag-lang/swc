#include "pch.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

void LangSpec::setup()
{
    setupKeywords();
    setupCharFlags();
}

void LangSpec::setupKeywords()
{
#define SWC_TOKEN_DEF(__id, __name, __kind)                             \
    if (Token::isSpecialWord(TokenId::__id))                            \
    {                                                                   \
        auto hash64 = Math::hash(__name);                               \
        keywordMap_.insert_or_assign(__name, hash64, TokenId::__id);    \
        keywordIdMap_[TokenId::__id] = __name;                          \
        SWC_ASSERT(keywordMap_.contains(__name, hash64));               \
        SWC_ASSERT(*keywordMap_.find(__name, hash64) == TokenId::__id); \
    }

#include "Compiler/Lexer/Tokens.Def.inc"

#undef SWC_TOKEN_DEF
}

void LangSpec::setupCharFlags()
{
    // Initialize all flags to 0
    for (auto& charFlag : charFlags_)
        charFlag = CharFlagsE::Zero;

    // ASCII characters (0-127)
    for (uint8_t i = 0; i < 128; i++)
        charFlags_[i].add(CharFlagsE::Ascii);

    // Blank characters
    charFlags_[' '].add(CharFlagsE::Blank);  // Space (0x20)
    charFlags_['\t'].add(CharFlagsE::Blank); // Horizontal tab (0x09)
    charFlags_['\f'].add(CharFlagsE::Blank); // Form feed (0x0C)
    charFlags_['\v'].add(CharFlagsE::Blank); // Vertical tab (0x0B)
    charFlags_['\r'].add(CharFlagsE::Eol);
    charFlags_['\n'].add(CharFlagsE::Eol);

    // Digits (0-9)
    for (char8_t c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsE::Digit);

    // Uppercase letters (A-Z)
    for (char8_t c = 'A'; c <= 'Z'; c++)
        charFlags_[c].add(CharFlagsE::Letter);

    // Lowercase letters (a-z)
    for (char8_t c = 'a'; c <= 'z'; c++)
        charFlags_[c].add(CharFlagsE::Letter);

    // Underscore is considered a letter in identifiers
    charFlags_['_'].add(CharFlagsE::Letter);
    charFlags_['_'].add(CharFlagsE::NumberSep);

    // Hexadecimal number
    for (char8_t c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsE::HexNumber);
    for (char8_t c = 'a'; c <= 'f'; c++)
        charFlags_[c].add(CharFlagsE::HexNumber);
    for (char8_t c = 'A'; c <= 'F'; c++)
        charFlags_[c].add(CharFlagsE::HexNumber);

    // Binary number
    for (char8_t c = '0'; c <= '1'; c++)
        charFlags_[c].add(CharFlagsE::BinNumber);

    // Identifier
    charFlags_['_'].add(CharFlagsE::IdentifierStart);
    charFlags_['_'].add(CharFlagsE::IdentifierPart);
    charFlags_['#'].add(CharFlagsE::IdentifierStart);
    charFlags_['@'].add(CharFlagsE::IdentifierStart);
    charFlags_['-'].add(CharFlagsE::Option);

    for (char8_t c = 'a'; c <= 'z'; c++)
    {
        charFlags_[c].add(CharFlagsE::IdentifierStart);
        charFlags_[c].add(CharFlagsE::IdentifierPart);
        charFlags_[c].add(CharFlagsE::Option);
    }

    for (char8_t c = 'A'; c <= 'Z'; c++)
    {
        charFlags_[c].add(CharFlagsE::IdentifierStart);
        charFlags_[c].add(CharFlagsE::IdentifierPart);
        charFlags_[c].add(CharFlagsE::Option);
    }

    for (char8_t c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsE::IdentifierPart);

    // Escape character
    charFlags_['0'].add(CharFlagsE::Escape);
    charFlags_['a'].add(CharFlagsE::Escape);
    charFlags_['b'].add(CharFlagsE::Escape);
    charFlags_['\\'].add(CharFlagsE::Escape);
    charFlags_['t'].add(CharFlagsE::Escape);
    charFlags_['n'].add(CharFlagsE::Escape);
    charFlags_['f'].add(CharFlagsE::Escape);
    charFlags_['r'].add(CharFlagsE::Escape);
    charFlags_['v'].add(CharFlagsE::Escape);
    charFlags_['\''].add(CharFlagsE::Escape);
    charFlags_['\"'].add(CharFlagsE::Escape);
    charFlags_['x'].add(CharFlagsE::Escape);
    charFlags_['u'].add(CharFlagsE::Escape);
    charFlags_['U'].add(CharFlagsE::Escape);
}

TokenId LangSpec::keyword(std::string_view name, uint32_t hash) const
{
    const auto ptr = keywordMap_.find(name, hash);
    if (!ptr)
        return TokenId::Identifier;
    return *ptr;
}

TokenId LangSpec::keyword(std::string_view name) const
{
    return keyword(name, Math::hash(name));
}

bool LangSpec::isReservedNamespace(std::string_view ns)
{
    Utf8 name = ns;
    name.make_lower();
    return name == "swag";
}

bool LangSpec::isSpecialFunctionName(std::string_view name)
{
    if (name.size() < 3)
        return false;
    if (name[0] != 'o' || name[1] != 'p')
        return false;
    return std::isupper(static_cast<unsigned char>(name[2])) != 0;
}

bool LangSpec::isOpVisitName(std::string_view name)
{
    return name.rfind("opVisit", 0) == 0;
}

bool LangSpec::matchSpecialFunction(std::string_view name, SpecialFuncKind& outKind)
{
    if (isOpVisitName(name))
    {
        outKind = SpecialFuncKind::OpVisit;
        return true;
    }

    if (name == "opInitGenerated")
        outKind = SpecialFuncKind::OpInitGenerated;
    else if (name == "opDropGenerated")
        outKind = SpecialFuncKind::OpDropGenerated;
    else if (name == "opPostCopyGenerated")
        outKind = SpecialFuncKind::OpPostCopyGenerated;
    else if (name == "opPostMoveGenerated")
        outKind = SpecialFuncKind::OpPostMoveGenerated;
    else if (name == "opBinary")
        outKind = SpecialFuncKind::OpBinary;
    else if (name == "opUnary")
        outKind = SpecialFuncKind::OpUnary;
    else if (name == "opAssign")
        outKind = SpecialFuncKind::OpAssign;
    else if (name == "opIndexAssign")
        outKind = SpecialFuncKind::OpIndexAssign;
    else if (name == "opCast")
        outKind = SpecialFuncKind::OpCast;
    else if (name == "opEquals")
        outKind = SpecialFuncKind::OpEquals;
    else if (name == "opCmp")
        outKind = SpecialFuncKind::OpCmp;
    else if (name == "opPostCopy")
        outKind = SpecialFuncKind::OpPostCopy;
    else if (name == "opPostMove")
        outKind = SpecialFuncKind::OpPostMove;
    else if (name == "opDrop")
        outKind = SpecialFuncKind::OpDrop;
    else if (name == "opCount")
        outKind = SpecialFuncKind::OpCount;
    else if (name == "opData")
        outKind = SpecialFuncKind::OpData;
    else if (name == "opAffect")
        outKind = SpecialFuncKind::OpAffect;
    else if (name == "opAffectLiteral")
        outKind = SpecialFuncKind::OpAffectLiteral;
    else if (name == "opSlice")
        outKind = SpecialFuncKind::OpSlice;
    else if (name == "opIndex")
        outKind = SpecialFuncKind::OpIndex;
    else if (name == "opIndexAffect")
        outKind = SpecialFuncKind::OpIndexAffect;
    else if (name == "opInit")
        outKind = SpecialFuncKind::OpInit;
    else
        return false;

    return true;
}

SWC_END_NAMESPACE();
