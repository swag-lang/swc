#pragma once

SWC_BEGIN_NAMESPACE();

class SourceFile;

// Your existing Flags<>. Keep this as-is.
enum class TokenIdFlagsEnum : uint32_t
{
    Zero      = 0,
    ArityNone = 1u << 0,
    ArityOne  = 1u << 1,
    ArityTwo  = 1u << 2,
    ArityMany = 1u << 3,
};

using TokenIdFlags = Flags<TokenIdFlagsEnum>;

struct TokenIdInfo
{
    std::string_view name;
    TokenIdFlags     flags;
};

// Convenience macros for the inc file (short & portable).
#define SWC_ARITY_NONE              \
    TokenIdFlags                    \
    {                               \
        TokenIdFlagsEnum::ArityNone \
    }
#define SWC_ARITY_ONE              \
    TokenIdFlags                   \
    {                              \
        TokenIdFlagsEnum::ArityOne \
    }
#define SWC_ARITY_TWO              \
    TokenIdFlags                   \
    {                              \
        TokenIdFlagsEnum::ArityTwo \
    }
#define SWC_ARITY_MANY              \
    TokenIdFlags                    \
    {                               \
        TokenIdFlagsEnum::ArityMany \
    }

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(Enum, Flags) Enum,
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array<TokenIdInfo, static_cast<size_t>(TokenId::Count)> TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(Enum, Flags) TokenIdInfo{#Enum, Flags},
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
};

struct Token
{
    uint32_t start = 0;
    uint32_t len   = 0;

    TokenId id = TokenId::Invalid;

    std::string_view toString(const SourceFile* file) const;
};

SWC_END_NAMESPACE();
