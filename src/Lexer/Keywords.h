#pragma once
#include "Lexer/KeyTable.h"

enum class SubTokenIdentifierId : uint16_t
{
    Invalid = 0,
    If,
};

using KeywordFlags = Flags<uint32_t>;

constexpr std::array<KwPair, 1> K_KEYWORDS = {{
    {"if", SubTokenIdentifierId::If, 0},
}};

constexpr KwTable<1024> KEYWORD_TABLE{K_KEYWORDS};
