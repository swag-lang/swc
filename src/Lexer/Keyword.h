#pragma once
#include "Lexer/KeywordTable.h"

SWC_BEGIN_NAMESPACE()

enum class KeywordIdFlags : uint32_t
{
    Zero = 0,
};
SWC_ENABLE_BITMASK(KeywordIdFlags);

constexpr std::array<KeywordIdInfo, 249> KEYWORD_ID_INFOS = {{
#define SWC_KEYWORD_DEF(name, enum, flags) KeywordIdInfo{name, TokenId::enum, KeywordIdFlags::flags},
#include "KeywordIds.inc"

#undef SWC_KEYWORD_DEF
}};

constexpr KeywordTable<1024> KEYWORD_TABLE{KEYWORD_ID_INFOS};

SWC_END_NAMESPACE()
