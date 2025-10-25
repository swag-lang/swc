#pragma once

SWC_BEGIN_NAMESPACE();

class SourceFile;

// Your existing Flags<>. Keep this as-is.
enum class TokenIdFlagsEnum : uint32_t
{
    Zero = 0,
};

using TokenIdFlags = Flags<TokenIdFlagsEnum>;

struct TokenIdInfo
{
    std::string_view name;
    TokenIdFlags     flags;
};

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(enum, flags) enum,
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array<TokenIdInfo, static_cast<size_t>(TokenId::Count)> TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(enum, flags) TokenIdInfo{#enum, TokenIdFlagsEnum::flags},
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
};

struct Token
{
    uint32_t start = 0;
    uint32_t len   = 0;

    TokenId id = TokenId::Count;

    std::string_view toString(const SourceFile* file) const;
};

SWC_END_NAMESPACE();
