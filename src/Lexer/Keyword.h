// ReSharper disable CppClangTidyModernizeUseDesignatedInitializers
#pragma once
#include "Lexer/KeywordTable.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

enum class KeywordIdFlags : uint32_t
{
    Zero = 0,
};
SWC_ENABLE_BITMASK(KeywordIdFlags);

constexpr std::array<KeywordIdInfo, 249> K_KEYWORDS = {{
#define SWC_KEYWORD_DEF(name, enum, flags) KeywordIdInfo{name, TokenId::enum, KeywordIdFlags::flags},
#include "KeywordIds.inc"

#undef SWC_KEYWORD_DEF
}};

constexpr KeywordTable<1024> KEYWORD_TABLE{K_KEYWORDS};

SWC_END_NAMESPACE();
