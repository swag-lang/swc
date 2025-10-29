#include "pch.h"
#include "Lexer/LangSpec.h"
#include "Core/Hash.h"

#include "Lexer/Keyword.h"

SWC_BEGIN_NAMESPACE()

void LangSpec::setup()
{
    setupKeywords();
    setupCharFlags();
}

void LangSpec::setupKeywords()
{
#define SWC_KEYWORD_DEF(__name, __id, __flags) \
    keywordMap_.insert_or_assign(__name, hash(__name), {__name, TokenId::__id, KeywordIdFlags::__flags});

#include "KeywordIds.inc"

#undef SWC_KEYWORD_DEF
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

bool LangSpec::isBlank(const uint8_t* buffer, const uint8_t* end, uint32_t& offset) const
{
    if (isBlank(buffer[0]))
    {
        offset = 1;
        return true;
    }

    if (buffer < end + 1 && buffer[0] == 0xC2 && buffer[1] == 0xA0)
    {
        offset = 2;
        return true;
    }

    return false;
}

TokenId LangSpec::keyword(std::string_view name, uint64_t hash)
{
    const auto ptr = keywordMap_.find(name, hash);
    if (!ptr)
        return TokenId::Identifier;
    return ptr->id;
}

std::string_view LangSpec::keywordName(TokenId tknId)
{
    for (const auto& [name, id, flags] : KEYWORD_ID_INFOS)
    {
        if (id == tknId)
            return name;
    }

    return "";
}

SWC_END_NAMESPACE()
