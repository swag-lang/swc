#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;

enum class TokenIdFlags : uint32_t
{
    Zero         = 0,
    Symbol       = 1 << 0,
    Keyword      = 1 << 1,
    Trivia       = 1 << 2,
    Compiler     = 1 << 3,
    Intrinsic    = 1 << 4,
    Type         = 1 << 5,
    Literal      = 1 << 6,
    Modifier     = 1 << 7,
    ReservedWord = Keyword | Compiler | Intrinsic | Type | Modifier,
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

enum class TokenFlags : uint16_t
{
    Zero        = 0,
    BlankBefore = 1 << 0,
    BlankAfter  = 1 << 1,
    EolBefore   = 1 << 2,
    EolAfter    = 1 << 3,
    EolInside   = 1 << 4,
};
SWC_ENABLE_BITMASK(TokenFlags);

struct Token
{
    uint32_t byteStart  = 0; // Byte offset in the source file buffer
    uint32_t byteLength = 0; // Length in bytes

    TokenId    id    = TokenId::Invalid;
    TokenFlags flags = TokenFlags::Zero;

    std::string_view        toString(const SourceFile& file) const;
    SourceCodeLocation      toLocation(const Context& ctx, const SourceFile& file) const;
    static TokenIdFlags     toFlags(TokenId tkn) { return TOKEN_ID_INFOS[static_cast<size_t>(tkn)].flags; }
    static std::string_view toName(TokenId tknId);
    static std::string_view toFamily(TokenId tknId);
    static std::string_view toAFamily(TokenId tknId);
    static TokenId          toRelated(TokenId tkn);

    bool isSymbol() const { return has_any(toFlags(id), TokenIdFlags::Symbol); }
    bool isKeyword() const { return has_any(toFlags(id), TokenIdFlags::Keyword); }
    bool isCompiler() const { return has_any(toFlags(id), TokenIdFlags::Compiler); }
    bool isIntrinsic() const { return has_any(toFlags(id), TokenIdFlags::Intrinsic); }
    bool isType() const { return has_any(toFlags(id), TokenIdFlags::Type); }
    bool isReservedWord() const { return has_any(toFlags(id), TokenIdFlags::ReservedWord); }
    bool startsLine() const { return has_any(flags, TokenFlags::EolBefore); }
};

SWC_END_NAMESPACE()
