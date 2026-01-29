#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE();
class SourceView;

class SourceFile;

enum class TokenIdKind
{
    Zero = 0,
    Trivia,
    Symbol,
    Keyword,
    KeywordLogic,
    Compiler,
    CompilerFunc,
    CompilerIntrinsic,
    CompilerIntrinsicReturn,
    Intrinsic,
    IntrinsicReturn,
    Type,
    Literal,
    Modifier,
    Reserved,
    CompilerAlias,
    CompilerUniq,
};

struct TokenIdInfo
{
    std::string_view enumName;
    std::string_view displayName;
    TokenIdKind      kind;
};

enum class TokenId : uint16_t
{
#define SWC_TOKEN_DEF(__enum, __name, __kind) __enum,
#include "Lexer/Tokens.Def.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(__enum, __name, __kind) TokenIdInfo{#__enum, __name, TokenIdKind::__kind},
#include "Lexer/Tokens.Def.inc"

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

struct Token;
using TokenRef = StrongRef<Token>;

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

    bool               isNot(TokenId id) const { return this->id != id; }
    std::string_view   string(const SourceView& srcView) const;
    uint32_t           crc(const SourceView& srcView) const;
    SourceCodeLocation location(const TaskContext& ctx, const SourceView& srcView) const;
    bool               hasFlag(TokenFlags flag) const { return flags.has(flag); }

    static TokenIdKind      toKind(TokenId id) { return TOKEN_ID_INFOS[static_cast<size_t>(id)].kind; }
    static std::string_view toName(TokenId id);
    static std::string_view toFamily(TokenId id);
    static TokenId          toRelated(TokenId id);

    bool startsLine() const { return flags.has(TokenFlagsE::EolBefore); }

    static bool isLiteral(TokenId id) { return toKind(id) == TokenIdKind::Literal; }
    static bool isSymbol(TokenId id) { return toKind(id) == TokenIdKind::Symbol; }
    static bool isKeywordLogic(TokenId id) { return toKind(id) == TokenIdKind::KeywordLogic; }
    static bool isKeyword(TokenId id) { return toKind(id) == TokenIdKind::Keyword || isKeywordLogic(id); }
    static bool isCompilerIntrinsicReturn(TokenId id) { return toKind(id) == TokenIdKind::CompilerIntrinsicReturn; }
    static bool isCompilerIntrinsic(TokenId id) { return toKind(id) == TokenIdKind::CompilerIntrinsic || isCompilerIntrinsicReturn(id); }
    static bool isCompilerFunc(TokenId id) { return toKind(id) == TokenIdKind::CompilerFunc; }
    static bool isCompilerAlias(TokenId id) { return toKind(id) == TokenIdKind::CompilerAlias; }
    static bool isCompilerUniq(TokenId id) { return toKind(id) == TokenIdKind::CompilerUniq; }
    static bool isCompiler(TokenId id) { return toKind(id) == TokenIdKind::Compiler || isCompilerIntrinsic(id) || isCompilerFunc(id) || isCompilerAlias(id) || isCompilerUniq(id); }
    static bool isIntrinsic(TokenId id) { return toKind(id) == TokenIdKind::Intrinsic || isIntrinsicReturn(id); }
    static bool isIntrinsicReturn(TokenId id) { return toKind(id) == TokenIdKind::IntrinsicReturn; }
    static bool isType(TokenId id) { return toKind(id) == TokenIdKind::Type; }
    static bool isModifier(TokenId id) { return toKind(id) == TokenIdKind::Modifier; }
    static bool isSpecialWord(TokenId id) { return isKeyword(id) || isCompiler(id) || isIntrinsic(id) || isType(id) || isModifier(id); }
    static bool isReserved(TokenId id) { return toKind(id) == TokenIdKind::Reserved; }

#if SWC_HAS_TOKEN_DEBUG_INFO
    const char8_t*     dbgPtr     = nullptr;
    SourceView*        dbgSrcView = nullptr;
    SourceCodeLocation dbgLoc;
#endif
};

SWC_END_NAMESPACE();
