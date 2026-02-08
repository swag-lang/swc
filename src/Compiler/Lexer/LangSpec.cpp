#include "pch.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
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

bool LangSpec::matchSpecialFunction(IdentifierRef idRef, const IdentifierManager& idMgr, SpecialFuncKind& outKind)
{
    if (idRef.isInvalid())
        return false;

    if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpVisit))
    {
        outKind = SpecialFuncKind::OpVisit;
        return true;
    }

    if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpBinary))
        outKind = SpecialFuncKind::OpBinary;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpUnary))
        outKind = SpecialFuncKind::OpUnary;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpAssign))
        outKind = SpecialFuncKind::OpAssign;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpIndexAssign))
        outKind = SpecialFuncKind::OpIndexAssign;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpCast))
        outKind = SpecialFuncKind::OpCast;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpEquals))
        outKind = SpecialFuncKind::OpEquals;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpCmp))
        outKind = SpecialFuncKind::OpCmp;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpPostCopy))
        outKind = SpecialFuncKind::OpPostCopy;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpPostMove))
        outKind = SpecialFuncKind::OpPostMove;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpDrop))
        outKind = SpecialFuncKind::OpDrop;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpCount))
        outKind = SpecialFuncKind::OpCount;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpData))
        outKind = SpecialFuncKind::OpData;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpAffect))
        outKind = SpecialFuncKind::OpAffect;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpAffectLiteral))
        outKind = SpecialFuncKind::OpAffectLiteral;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpSlice))
        outKind = SpecialFuncKind::OpSlice;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpIndex))
        outKind = SpecialFuncKind::OpIndex;
    else if (idRef == idMgr.predefined(IdentifierManager::PredefinedName::OpIndexAffect))
        outKind = SpecialFuncKind::OpIndexAffect;
    else
    {
        const std::string_view name = idMgr.get(idRef).name;
        if (isOpVisitName(name))
        {
            outKind = SpecialFuncKind::OpVisit;
            return true;
        }

        return false;
    }

    return true;
}

std::string_view LangSpec::specialFunctionSignatureHint(SpecialFuncKind kind)
{
    switch (kind)
    {
        case SpecialFuncKind::OpDrop:
            return "func opDrop(me) -> void";
        case SpecialFuncKind::OpPostCopy:
            return "func opPostCopy(me) -> void";
        case SpecialFuncKind::OpPostMove:
            return "func opPostMove(me) -> void";
        case SpecialFuncKind::OpCount:
            return "func opCount(me) -> u64";
        case SpecialFuncKind::OpData:
            return "func opData(me) -> *<type>";
        case SpecialFuncKind::OpCast:
            return "func opCast(me) -> <type>";
        case SpecialFuncKind::OpEquals:
            return "func opEquals(me, value: <type>) -> bool";
        case SpecialFuncKind::OpCmp:
            return "func opCmp(me, value: <type>) -> s32";
        case SpecialFuncKind::OpBinary:
            return "func opBinary(me, other: <type>) -> <struct>";
        case SpecialFuncKind::OpUnary:
            return "func opUnary(me) -> <struct>";
        case SpecialFuncKind::OpAssign:
            return "func opAssign(me, value: <type>) -> void";
        case SpecialFuncKind::OpAffect:
            return "func opAffect(me, value: <type>) -> void";
        case SpecialFuncKind::OpAffectLiteral:
            return "func opAffectLiteral(me, value: <type>) -> void";
        case SpecialFuncKind::OpSlice:
            return "func opSlice(me, low: u64, up: u64) -> <string or slice>";
        case SpecialFuncKind::OpIndex:
            return "func opIndex(me, index: <type>) -> <type>";
        case SpecialFuncKind::OpIndexAssign:
            return "func opIndexAssign(me, index: <type>, value: <type>) -> void";
        case SpecialFuncKind::OpIndexAffect:
            return "func opIndexAffect(me, index: <type>, value: <type>) -> void";
        case SpecialFuncKind::OpVisit:
            return "func opVisit(me, stmt: #code) -> void";
        default:
            return "valid special function signature";
    }
}

SWC_END_NAMESPACE();
