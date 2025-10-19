#include "pch.h"

#include "LangSpec.h"

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
    for (int i = 0; i < 128; i++)
        charFlags_[i].add(CHAR_ASCII);

    // Blank characters
    charFlags_[' '].add(CHAR_BLANK);  // Space (0x20)
    charFlags_['\t'].add(CHAR_BLANK); // Horizontal tab (0x09)
    charFlags_['\r'].add(CHAR_BLANK); // Carriage return (0x0D)
    charFlags_['\f'].add(CHAR_BLANK); // Form feed (0x0C)
    charFlags_['\v'].add(CHAR_BLANK); // Vertical tab (0x0B)

    // Digits (0-9)
    for (char c = '0'; c <= '9'; c++)
        charFlags_[static_cast<uint8_t>(c)].add(CHAR_DIGIT);

    // Uppercase letters (A-Z)
    for (char c = 'A'; c <= 'Z'; c++)
        charFlags_[static_cast<uint8_t>(c)].add(CHAR_LETTER);

    // Lowercase letters (a-z)
    for (char c = 'a'; c <= 'z'; c++)
        charFlags_[static_cast<uint8_t>(c)].add(CHAR_LETTER);

    // Underscore is often considered a letter in identifiers
    charFlags_['_'].add(CHAR_LETTER);
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