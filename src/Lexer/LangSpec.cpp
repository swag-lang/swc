#include "pch.h"
#include "Lexer/LangSpec.h"
#include "Core/Hash.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

void LangSpec::setup()
{
    setupKeywords();
    setupCharFlags();
}

void LangSpec::setupKeywords()
{
#define SWC_TOKEN_DEF(__id, __name, __flags)                               \
    if (has_any(TokenIdFlags::__flags, TokenIdFlags::ReservedWord))        \
    {                                                                      \
        keywordMap_.insert_or_assign(__name, hash(__name), TokenId::__id); \
        keywordIdMap_[TokenId::__id] = __name;                             \
    }

#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
}

void LangSpec::setupCharFlags()
{
    // Initialize all flags to 0
    for (auto& charFlag : charFlags_)
        charFlag = CharFlags::Zero;

    // ASCII characters (0-127)
    for (uint8_t i = 0; i < 128; i++)
        charFlags_[i] |= CharFlags::Ascii;

    // Blank characters
    charFlags_[' '] |= CharFlags::Blank;  // Space (0x20)
    charFlags_['\t'] |= CharFlags::Blank; // Horizontal tab (0x09)
    charFlags_['\f'] |= CharFlags::Blank; // Form feed (0x0C)
    charFlags_['\v'] |= CharFlags::Blank; // Vertical tab (0x0B)
    charFlags_['\r'] |= CharFlags::Eol;
    charFlags_['\n'] |= CharFlags::Eol;

    // Digits (0-9)
    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c] |= CharFlags::Digit;

    // Uppercase letters (A-Z)
    for (unsigned char c = 'A'; c <= 'Z'; c++)
        charFlags_[c] |= CharFlags::Letter;

    // Lowercase letters (a-z)
    for (unsigned char c = 'a'; c <= 'z'; c++)
        charFlags_[c] |= CharFlags::Letter;

    // Underscore is considered a letter in identifiers
    charFlags_['_'] |= CharFlags::Letter | CharFlags::NumberSep;

    // Hexadecimal number
    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c] |= CharFlags::HexNumber;
    for (unsigned char c = 'a'; c <= 'f'; c++)
        charFlags_[c] |= CharFlags::HexNumber;
    for (unsigned char c = 'A'; c <= 'F'; c++)
        charFlags_[c] |= CharFlags::HexNumber;

    // Binary number
    for (unsigned char c = '0'; c <= '1'; c++)
        charFlags_[c] |= CharFlags::BinNumber;

    // Identifier
    charFlags_['_'] |= CharFlags::IdentifierStart | CharFlags::IdentifierPart;
    charFlags_['#'] |= CharFlags::IdentifierStart;
    charFlags_['@'] |= CharFlags::IdentifierStart;
    charFlags_['-'] |= CharFlags::Option;

    for (unsigned char c = 'a'; c <= 'z'; c++)
    {
        charFlags_[c] |= CharFlags::IdentifierStart;
        charFlags_[c] |= CharFlags::IdentifierPart;
        charFlags_[c] |= CharFlags::Option;
    }

    for (unsigned char c = 'A'; c <= 'Z'; c++)
    {
        charFlags_[c] |= CharFlags::IdentifierStart;
        charFlags_[c] |= CharFlags::IdentifierPart;
        charFlags_[c] |= CharFlags::Option;
    }

    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c] |= CharFlags::IdentifierPart;

    // Escape character
    charFlags_['0'] |= CharFlags::Escape;
    charFlags_['a'] |= CharFlags::Escape;
    charFlags_['b'] |= CharFlags::Escape;
    charFlags_['\\'] |= CharFlags::Escape;
    charFlags_['t'] |= CharFlags::Escape;
    charFlags_['n'] |= CharFlags::Escape;
    charFlags_['f'] |= CharFlags::Escape;
    charFlags_['r'] |= CharFlags::Escape;
    charFlags_['v'] |= CharFlags::Escape;
    charFlags_['\''] |= CharFlags::Escape;
    charFlags_['\"'] |= CharFlags::Escape;
    charFlags_['x'] |= CharFlags::Escape;
    charFlags_['u'] |= CharFlags::Escape;
    charFlags_['U'] |= CharFlags::Escape;
}

TokenId LangSpec::keyword(std::string_view name, uint64_t hash)
{
    const auto ptr = keywordMap_.find(name, hash);
    if (!ptr)
        return TokenId::Identifier;
    return *ptr;
}

SWC_END_NAMESPACE()
