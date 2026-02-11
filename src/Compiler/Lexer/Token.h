#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
class SourceFile;

enum class TokenIdFlagsE : uint32_t
{
    Zero                    = 0,
    Trivia                  = 1 << 0,
    Symbol                  = 1 << 1,
    Keyword                 = 1 << 2,
    KeywordLogic            = 1 << 3,
    Compiler                = 1 << 4,
    CompilerFunc            = 1 << 5,
    CompilerIntrinsic       = 1 << 6,
    CompilerIntrinsicReturn = 1 << 7,
    Intrinsic               = 1 << 8,
    IntrinsicReturn         = 1 << 9,
    Type                    = 1 << 10,
    Literal                 = 1 << 11,
    Modifier                = 1 << 12,
    Reserved                = 1 << 13,
    CompilerAlias           = 1 << 14,
    CompilerUniq            = 1 << 15,
    PureIntrinsic           = 1 << 16,
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
#define SWC_TOKEN_DEF(__enum, __name, __flags) __enum,
#include "Compiler/Lexer/Tokens.Def.inc"

#undef SWC_TOKEN_DEF
    Count
};

constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(__enum, __name, __flags) TokenIdInfo{#__enum, __name, __flags},
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

    static TokenIdFlags     toFlags(TokenId id) { return TOKEN_ID_INFOS[static_cast<size_t>(id)].flags; }
    static std::string_view toName(TokenId id);
    static std::string_view toFamily(TokenId id);
    static TokenId          toRelated(TokenId id);
    static TokenId          assignToBinary(TokenId op);

    bool startsLine() const { return flags.has(TokenFlagsE::EolBefore); }

    static bool isLiteral(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Literal); }
    static bool isSymbol(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Symbol); }
    static bool isKeywordLogic(TokenId id) { return toFlags(id).has(TokenIdFlagsE::KeywordLogic); }
    static bool isKeyword(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Keyword); }
    static bool isCompilerIntrinsicReturn(TokenId id) { return toFlags(id).has(TokenIdFlagsE::CompilerIntrinsicReturn); }
    static bool isCompilerIntrinsic(TokenId id) { return toFlags(id).has(TokenIdFlagsE::CompilerIntrinsic) || isCompilerIntrinsicReturn(id); }
    static bool isCompilerFunc(TokenId id) { return toFlags(id).has(TokenIdFlagsE::CompilerFunc); }
    static bool isCompilerAlias(TokenId id) { return toFlags(id).has(TokenIdFlagsE::CompilerAlias); }
    static bool isCompilerUniq(TokenId id) { return toFlags(id).has(TokenIdFlagsE::CompilerUniq); }
    static bool isCompiler(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Compiler) || isCompilerIntrinsic(id) || isCompilerFunc(id) || isCompilerAlias(id) || isCompilerUniq(id); }
    static bool isIntrinsic(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Intrinsic) || isIntrinsicReturn(id); }
    static bool isIntrinsicReturn(TokenId id) { return toFlags(id).has(TokenIdFlagsE::IntrinsicReturn); }
    static bool isType(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Type); }
    static bool isModifier(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Modifier); }
    static bool isSpecialWord(TokenId id) { return isKeyword(id) || isCompiler(id) || isIntrinsic(id) || isType(id) || isModifier(id); }
    static bool isReserved(TokenId id) { return toFlags(id).has(TokenIdFlagsE::Reserved); }
    static bool isPureIntrinsic(TokenId id) { return toFlags(id).has(TokenIdFlagsE::PureIntrinsic); }

#if SWC_HAS_TOKEN_DEBUG_INFO
    const char8_t*  dbgPtr     = nullptr;
    SourceView*     dbgSrcView = nullptr;
    SourceCodeRange dbgLoc;
#endif
};

SWC_END_NAMESPACE();
