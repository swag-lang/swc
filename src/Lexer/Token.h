#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;

enum class TokenIdFlagsE : uint32_t
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
    Reserved     = 1 << 8,
    ReservedWord = Keyword | Compiler | Intrinsic | Type | Modifier,
};
using TokenIdFlags = EnumFlags<TokenIdFlagsE>;

struct TokenIdInfo
{
    std::string_view enumName;
    std::string_view displayName;
    TokenIdFlags     flags;
};

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(enum, name, flags) enum,
#include "TokenIds.def"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(enum, name, flags) TokenIdInfo{#enum, name, TokenIdFlagsE::flags},
#include "TokenIds.def"

#undef SWC_TOKEN_DEF
};

enum class TokenFlagsE : uint16_t
{
    Zero        = 0,
    BlankBefore = 1 << 0,
    BlankAfter  = 1 << 1,
    EolBefore   = 1 << 2,
    EolAfter    = 1 << 3,
    EolInside   = 1 << 4,
};
using TokenFlags = EnumFlags<TokenFlagsE>;

struct Token
{
    uint32_t byteStart  = 0; // Byte offset in the source file buffer
    uint32_t byteLength = 0; // Length in bytes

    TokenId    id    = TokenId::Invalid;
    TokenFlags flags = TokenFlagsE::Zero;

    std::string_view   string(const SourceFile& file) const;
    SourceCodeLocation location(const Context& ctx, const SourceFile& file) const;
    bool               hasFlag(TokenFlags flag) const { return flags.has(flag); }
    bool               hasNotFlag(TokenFlags flag) const { return !flags.has(flag); }

    static TokenIdFlags     toFlags(TokenId tkn) { return TOKEN_ID_INFOS[static_cast<size_t>(tkn)].flags; }
    static std::string_view toName(TokenId tknId);
    static std::string_view toFamily(TokenId tknId);
    static std::string_view toAFamily(TokenId tknId);
    static TokenId          toRelated(TokenId tkn);

    bool startsLine() const { return flags.has(TokenFlagsE::EolBefore); }

    bool isSymbol() const { return toFlags(id).has(TokenIdFlagsE::Symbol); }
    bool isKeyword() const { return toFlags(id).has(TokenIdFlagsE::Keyword); }
    bool isCompiler() const { return toFlags(id).has(TokenIdFlagsE::Compiler); }
    bool isIntrinsic() const { return toFlags(id).has(TokenIdFlagsE::Intrinsic); }
    bool isType() const { return toFlags(id).has(TokenIdFlagsE::Type); }
    bool isModifier() const { return toFlags(id).has(TokenIdFlagsE::Modifier); }
    bool isReservedWord() const { return toFlags(id).has(TokenIdFlagsE::ReservedWord); }
    bool isReserved() const { return toFlags(id).has(TokenIdFlagsE::Reserved); }

    static bool isSymbol(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Symbol); }
    static bool isKeyword(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Keyword); }
    static bool isCompiler(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Compiler); }
    static bool isIntrinsic(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Intrinsic); }
    static bool isType(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Type); }
    static bool isModifier(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Modifier); }
    static bool isReservedWord(TokenId id) { return toFlags(id).has(TokenIdFlagsE::ReservedWord); }
    static bool isReserved(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Reserved); }
};

SWC_END_NAMESPACE()
