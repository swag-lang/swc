#pragma once

SWC_BEGIN_NAMESPACE();

class SourceFile;

//------------------------------------
// Token ids information's
//------------------------------------

enum class TokenIdFlags : uint32_t
{
    Zero   = 0,
    Symbol = 1 << 0,
};
SWC_ENABLE_BITMASK(TokenIdFlags);

struct TokenIdInfo
{
    std::string_view enumName;
    std::string_view displayName;
    TokenIdFlags     flags;
};

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(enum, name, flags) enum,
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(enum, name, flags) TokenIdInfo{#enum, name, TokenIdFlags::flags},
#include "TokenIds.inc"

#undef SWC_TOKEN_DEF
};

//------------------------------------
// Tokens
//------------------------------------

enum class TokenFlags : uint16_t
{
    Zero        = 0,
    BlankBefore = 1 << 0,
    BlankAfter  = 1 << 1,
    EolBefore   = 1 << 2,
    EolAfter    = 1 << 3,
};
SWC_ENABLE_BITMASK(TokenFlags);

#pragma pack(push, 1)
struct Token
{
    uint32_t byteStart  = 0; // Byte offset in the source file buffer
    uint32_t byteLength = 0; // Length in bytes

    TokenId    id    = TokenId::Invalid;
    TokenFlags flags = TokenFlags::Zero;

    std::string_view        toString(const SourceFile* file) const;
    static TokenIdFlags     toFlags(TokenId tkn) { return TOKEN_ID_INFOS[static_cast<size_t>(tkn)].flags; }
    static std::string_view toName(TokenId tknId);
    static TokenId          toRelated(TokenId tkn);
};
#pragma pack(pop)

SWC_END_NAMESPACE();
