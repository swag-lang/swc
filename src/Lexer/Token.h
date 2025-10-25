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

    TokenId id = TokenId::Invalid;

    std::string_view toString(const SourceFile* file) const;
};
#pragma pack(pop)

SWC_END_NAMESPACE();
