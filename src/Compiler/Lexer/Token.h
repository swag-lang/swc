#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
class SourceFile;

enum class TokenIdKindE : uint16_t
{
    Zero      = 0,
    Trivia    = 1 << 0,
    Symbol    = 1 << 1,
    Keyword   = 1 << 2,
    Logic     = 1 << 3,
    Compiler  = 1 << 4,
    Func      = 1 << 5,
    Intrinsic = 1 << 6,
    Return    = 1 << 7,
    Type      = 1 << 8,
    Literal   = 1 << 9,
    Modifier  = 1 << 10,
    Reserved  = 1 << 11,
    Alias     = 1 << 12,
    Uniq      = 1 << 13,

    KeywordLogic            = Keyword | Logic,
    CompilerFunc            = Compiler | Func,
    CompilerIntrinsic       = Compiler | Intrinsic,
    CompilerIntrinsicReturn = CompilerIntrinsic | Return,
    IntrinsicReturn         = Intrinsic | Return,
    CompilerAlias           = Compiler | Alias,
    CompilerUniq            = Compiler | Uniq,
};
using TokenIdKind = EnumFlags<TokenIdKindE>;

struct TokenIdInfo
{
    std::string_view enumName;
    std::string_view displayName;
    TokenIdKind      kind;
};

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(__enum, __name, __kind) __enum,
#include "Compiler/Lexer/Tokens.Def.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(__enum, __name, __kind) TokenIdInfo{#__enum, __name, TokenIdKindE::__kind},
#include "Compiler/Lexer/Tokens.Def.inc"

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
    Escaped     = 1 << 5,
};
using TokenFlags = EnumFlags<TokenFlagsE>;

struct Token
{
    uint32_t byteStart  = 0; // Byte offset in the source file buffer
    uint32_t byteLength = 0; // Length in bytes

    TokenId    id    = TokenId::Invalid;
    TokenFlags flags = TokenFlagsE::Zero;

    bool is(TokenId id) const { return this->id == id; }
    bool isAny(std::initializer_list<TokenId> list) const
    {
        return std::ranges::any_of(list, [this](auto id) { return this->id == id; });
    }

    bool             isNot(TokenId id) const { return this->id != id; }
    std::string_view string(const SourceView& srcView) const;
    uint32_t         crc(const SourceView& srcView) const;
    SourceCodeRange  codeRange(const TaskContext& ctx, const SourceView& srcView) const;
    bool             hasFlag(TokenFlags flag) const { return flags.has(flag); }

    static TokenIdKind      toKind(TokenId id) { return TOKEN_ID_INFOS[static_cast<size_t>(id)].kind; }
    static std::string_view toName(TokenId id);
    static std::string_view toFamily(TokenId id);
    static TokenId          toRelated(TokenId id);
    static TokenId          assignToBinary(TokenId op);

    bool startsLine() const { return flags.has(TokenFlagsE::EolBefore); }

    static bool isLiteral(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Literal); }
    static bool isSymbol(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Symbol); }
    static bool isKeywordLogic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::KeywordLogic); }
    static bool isKeyword(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Keyword); }
    static bool isCompilerIntrinsicReturn(TokenId id) { return toKind(id).hasAll(TokenIdKindE::CompilerIntrinsicReturn); }
    static bool isCompilerIntrinsic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::CompilerIntrinsic); }
    static bool isCompilerFunc(TokenId id) { return toKind(id).hasAll(TokenIdKindE::CompilerFunc); }
    static bool isCompilerAlias(TokenId id) { return toKind(id).hasAll(TokenIdKindE::CompilerAlias); }
    static bool isCompilerUniq(TokenId id) { return toKind(id).hasAll(TokenIdKindE::CompilerUniq); }
    static bool isCompiler(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler); }
    static bool isIntrinsic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Intrinsic); }
    static bool isIntrinsicReturn(TokenId id) { return toKind(id).hasAll(TokenIdKindE::IntrinsicReturn); }
    static bool isType(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Type); }
    static bool isModifier(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Modifier); }
    static bool isSpecialWord(TokenId id) { return isKeyword(id) || isCompiler(id) || isIntrinsic(id) || isType(id) || isModifier(id); }
    static bool isReserved(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Reserved); }

#if SWC_HAS_TOKEN_DEBUG_INFO
    const char8_t*  dbgPtr     = nullptr;
    SourceView*     dbgSrcView = nullptr;
    SourceCodeRange dbgLoc;
#endif
};

SWC_END_NAMESPACE();
