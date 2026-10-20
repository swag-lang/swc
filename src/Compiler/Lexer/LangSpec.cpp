#include "pch.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

void LangSpec::setup()
{
    setupKeywords();
    setupCharFlags();
}

void LangSpec::setupKeywords()
{
#define SWC_TOKEN_DEF(__id, __name, __kind)                                       \
    if (Token::isSpecialWord(TokenId::__id) &&                                    \
        (!Token::isIntrinsic(TokenId::__id) || Token::isCompiler(TokenId::__id))) \
    {                                                                             \
        auto hash64 = Math::hash(__name);                                         \
        keywordMap_.insert_or_assign(__name, hash64, TokenId::__id);              \
        SWC_ASSERT(keywordMap_.contains(__name, hash64));                         \
        SWC_ASSERT(*keywordMap_.find(__name, hash64) == TokenId::__id);           \
    }

#include "Compiler/Lexer/Tokens.Def.inc"

#undef SWC_TOKEN_DEF
}

consteval std::array<CharFlags, 256> LangSpec::makeCharFlags()
{
    std::array<CharFlags, 256> flags{};

    // ASCII characters (0-127)
    for (uint8_t i = 0; i < 128; i++)
        flags[i].add(CharFlagsE::Ascii);

    // Blank characters
    flags[' '].add(CharFlagsE::Blank);  // Space (0x20)
    flags['\t'].add(CharFlagsE::Blank); // Horizontal tab (0x09)
    flags['\f'].add(CharFlagsE::Blank); // Form feed (0x0C)
    flags['\v'].add(CharFlagsE::Blank); // Vertical tab (0x0B)

    flags['\r'].add(CharFlagsE::Eol);
    flags['\n'].add(CharFlagsE::Eol);

    // Digits (0-9)
    for (char8_t c = '0'; c <= '9'; c++)
        flags[c].add(CharFlagsE::Digit);

    // Uppercase letters (A-Z)
    for (char8_t c = 'A'; c <= 'Z'; c++)
        flags[c].add(CharFlagsE::Letter);

    // Lowercase letters (a-z)
    for (char8_t c = 'a'; c <= 'z'; c++)
        flags[c].add(CharFlagsE::Letter);

    // Underscore is considered a letter in identifiers
    flags['_'].add(CharFlagsE::Letter);
    flags['_'].add(CharFlagsE::NumberSep);

    // Hexadecimal number
    for (char8_t c = '0'; c <= '9'; c++)
        flags[c].add(CharFlagsE::HexNumber);

    for (char8_t c = 'a'; c <= 'f'; c++)
        flags[c].add(CharFlagsE::HexNumber);

    for (char8_t c = 'A'; c <= 'F'; c++)
        flags[c].add(CharFlagsE::HexNumber);

    // Binary number
    for (char8_t c = '0'; c <= '1'; c++)
        flags[c].add(CharFlagsE::BinNumber);

    // Identifier
    flags['_'].add(CharFlagsE::IdentifierStart);
    flags['_'].add(CharFlagsE::IdentifierPart);
    flags['#'].add(CharFlagsE::IdentifierStart);
    flags['-'].add(CharFlagsE::Option);

    for (char8_t c = 'a'; c <= 'z'; c++)
    {
        flags[c].add(CharFlagsE::IdentifierStart);
        flags[c].add(CharFlagsE::IdentifierPart);
        flags[c].add(CharFlagsE::Option);
    }

    for (char8_t c = 'A'; c <= 'Z'; c++)
    {
        flags[c].add(CharFlagsE::IdentifierStart);
        flags[c].add(CharFlagsE::IdentifierPart);
        flags[c].add(CharFlagsE::Option);
    }

    for (char8_t c = '0'; c <= '9'; c++)
        flags[c].add(CharFlagsE::IdentifierPart);

    // Escape character
    flags['0'].add(CharFlagsE::Escape);
    flags['a'].add(CharFlagsE::Escape);
    flags['b'].add(CharFlagsE::Escape);
    flags['\\'].add(CharFlagsE::Escape);
    flags['t'].add(CharFlagsE::Escape);
    flags['n'].add(CharFlagsE::Escape);
    flags['f'].add(CharFlagsE::Escape);
    flags['r'].add(CharFlagsE::Escape);
    flags['v'].add(CharFlagsE::Escape);
    flags['\''].add(CharFlagsE::Escape);
    flags['\"'].add(CharFlagsE::Escape);
    flags['x'].add(CharFlagsE::Escape);
    flags['u'].add(CharFlagsE::Escape);
    flags['U'].add(CharFlagsE::Escape);

    return flags;
}

void LangSpec::setupCharFlags()
{
    charFlags_ = makeCharFlags();
}

TokenId LangSpec::keyword(std::string_view name, uint32_t hash) const
{
    const auto* ptr = keywordMap_.find(name, hash);
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
    return ns.size() == 4 &&
           std::tolower(static_cast<unsigned char>(ns[0])) == 's' &&
           std::tolower(static_cast<unsigned char>(ns[1])) == 'w' &&
           std::tolower(static_cast<unsigned char>(ns[2])) == 'a' &&
           std::tolower(static_cast<unsigned char>(ns[3])) == 'g';
}

bool LangSpec::isSpecOpName(std::string_view name)
{
    if (name.size() < 3)
        return false;

    if (name[0] != 'o' || name[1] != 'p')
        return false;

    return std::isupper(static_cast<unsigned char>(name[2])) != 0;
}

SWC_END_NAMESPACE();
