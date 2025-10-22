#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Lexer/Keywords.h"

LangSpec::LangSpec()
{
    initCharFlags();
}

void LangSpec::initCharFlags()
{
    // Initialize all flags to 0
    for (auto& charFlag : charFlags_)
        charFlag.clear();

    // ASCII characters (0-127)
    for (uint8_t i = 0; i < 128; i++)
        charFlags_[i].add(CharFlagsEnum::Ascii);

    // Blank characters
    charFlags_[' '].add(CharFlagsEnum::Blank);  // Space (0x20)
    charFlags_['\t'].add(CharFlagsEnum::Blank); // Horizontal tab (0x09)
    charFlags_['\f'].add(CharFlagsEnum::Blank); // Form feed (0x0C)
    charFlags_['\v'].add(CharFlagsEnum::Blank); // Vertical tab (0x0B)

    // Digits (0-9)
    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsEnum::Digit);

    // Uppercase letters (A-Z)
    for (unsigned char c = 'A'; c <= 'Z'; c++)
        charFlags_[c].add(CharFlagsEnum::Letter);

    // Lowercase letters (a-z)
    for (unsigned char c = 'a'; c <= 'z'; c++)
        charFlags_[c].add(CharFlagsEnum::Letter);

    // Underscore is considered a letter in identifiers
    charFlags_['_'].add(CharFlagsEnum::Letter, CharFlagsEnum::NumberSep);

    // Hexadecimal number
    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsEnum::HexNumber);
    for (unsigned char c = 'a'; c <= 'f'; c++)
        charFlags_[c].add(CharFlagsEnum::HexNumber);
    for (unsigned char c = 'A'; c <= 'F'; c++)
        charFlags_[c].add(CharFlagsEnum::HexNumber);

    // Binary number
    for (unsigned char c = '0'; c <= '1'; c++)
        charFlags_[c].add(CharFlagsEnum::BinNumber);

    // Identifier
    charFlags_['_'].add(CharFlagsEnum::IdentifierStart, CharFlagsEnum::IdentifierPart);
    charFlags_['#'].add(CharFlagsEnum::IdentifierStart);
    charFlags_['@'].add(CharFlagsEnum::IdentifierStart);
    for (unsigned char c = 'a'; c <= 'z'; c++)
        charFlags_[c].add(CharFlagsEnum::IdentifierStart, CharFlagsEnum::IdentifierPart);
    for (unsigned char c = 'A'; c <= 'Z'; c++)
        charFlags_[c].add(CharFlagsEnum::IdentifierStart, CharFlagsEnum::IdentifierPart);
    for (unsigned char c = '0'; c <= '9'; c++)
        charFlags_[c].add(CharFlagsEnum::IdentifierPart);

    // Escape character
    charFlags_['0'].add(CharFlagsEnum::Escape);
    charFlags_['a'].add(CharFlagsEnum::Escape);
    charFlags_['b'].add(CharFlagsEnum::Escape);
    charFlags_['\\'].add(CharFlagsEnum::Escape);
    charFlags_['t'].add(CharFlagsEnum::Escape);
    charFlags_['n'].add(CharFlagsEnum::Escape);
    charFlags_['f'].add(CharFlagsEnum::Escape);
    charFlags_['r'].add(CharFlagsEnum::Escape);
    charFlags_['v'].add(CharFlagsEnum::Escape);
    charFlags_['\''].add(CharFlagsEnum::Escape);
    charFlags_['\"'].add(CharFlagsEnum::Escape);
    charFlags_['x'].add(CharFlagsEnum::Escape);
    charFlags_['u'].add(CharFlagsEnum::Escape);
    charFlags_['U'].add(CharFlagsEnum::Escape);
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

SubTokenIdentifierId LangSpec::keyword(std::string_view name)
{
    return KEYWORD_TABLE.find(name);
}