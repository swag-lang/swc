#pragma once

SWC_BEGIN_NAMESPACE();

class SourceFile;

enum class TokenIdFlagsEnum : uint32_t
{
    Zero = 0,
};

enum class TokenFlagsEnum : uint16_t
{
    Zero        = 0,
    BlankBefore = 1 << 0,
    BlankAfter  = 1 << 1,
    EolBefore   = 1 << 2,
    EolAfter    = 1 << 3,
};

using TokenIdFlags = Flags<TokenIdFlagsEnum>;
using TokenFlags   = Flags<TokenFlagsEnum>;

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

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(enum, flags) TokenIdInfo{#enum, TokenIdFlagsEnum::flags},
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
};

#pragma pack(push, 1)
struct Token
{
    uint32_t byteStart  = 0; // Byte offset in the source file buffer
    uint32_t byteLength = 0; // Length in bytes

    TokenId    id    = TokenId::Invalid;
    TokenFlags flags = TokenFlagsEnum::Zero;

    std::string_view toString(const SourceFile* file) const;
};
#pragma pack(pop)

SWC_END_NAMESPACE();
