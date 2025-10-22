#pragma once
#include "Lexer/KeyTable.h"

enum class SubTokenIdentifierId : uint16_t
{
    Invalid = 0,
    Identifier,
};

constexpr std::array<KwPair, 1> K_KEYWORDS = {{
    {"if", SubTokenIdentifierId::Identifier},
}};

constexpr KwTable<1024> KEYWORD_TABLE{K_KEYWORDS};
