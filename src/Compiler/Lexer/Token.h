#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/Flags.h"

SWC_BEGIN_NAMESPACE();

class SourceView;
class SourceFile;

enum class TokenIdKindE : uint32_t
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
    Uniq      = 1 << 13,

    // Operator families. '++' is deliberately absent: concatenation shares no operand rule
    // with the numeric operators, and every site that accepts it handles it on its own.
    OpArithmetic = 1 << 14, // + - * / %
    OpBitwise    = 1 << 15, // & | ^ << >>
    OpEquality   = 1 << 16, // == !=
    OpOrdering   = 1 << 17, // < <= > >= <=>
    OpLogical    = 1 << 18, // and or && ||
    OpAssign     = 1 << 19, // = and every compound assignment
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

inline constexpr std::array TOKEN_ID_INFOS = {
#define SWC_TOKEN_DEF(__enum, __name, __kind) TokenIdInfo{#__enum, __name, TokenIdKind{__kind}},
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
    // Set on a string literal introduced by '#raw': the content is taken verbatim, so no
    // escape sequence is recognized and no end-of-line is folded.
    Raw = 1 << 6,
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
        for (const TokenId candidate : list)
        {
            if (this->id == candidate)
                return true;
        }
        return false;
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
    static TokenId          canonicalBinary(TokenId op);

    bool startsLine() const { return flags.has(TokenFlagsE::EolBefore); }

    static bool isTrivia(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Trivia); }
    static bool isLiteral(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Literal); }
    static bool isSymbol(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Symbol); }
    static bool isKeywordLogic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Keyword | TokenIdKindE::Logic); }
    static bool isKeyword(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Keyword); }
    static bool isCompilerIntrinsicReturn(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return); }
    static bool isCompilerIntrinsic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler | TokenIdKindE::Intrinsic); }
    static bool isCompilerFunc(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler | TokenIdKindE::Func); }
    static bool isCompilerUniq(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler | TokenIdKindE::Uniq); }
    static bool isCompiler(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Compiler); }
    static bool isIntrinsic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Intrinsic); }
    static bool isIntrinsicReturn(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Intrinsic | TokenIdKindE::Return); }
    static bool isType(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Type); }
    static bool isModifier(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Modifier); }
    static bool isSpecialWord(TokenId id) { return isKeyword(id) || isCompiler(id) || isIntrinsic(id) || isType(id) || isModifier(id); }
    static bool isReserved(TokenId id) { return toKind(id).hasAll(TokenIdKindE::Reserved); }
    // The compiler function blocks that turn into a symbol in the native artifact, as opposed
    // to the ones the compiler consumes itself ('#run', '#ast', '#message').
    static bool isNativeArtifactCompilerFunc(TokenId id)
    {
        switch (id)
        {
            case TokenId::CompilerFuncTest:
            case TokenId::CompilerFuncInit:
            case TokenId::CompilerFuncDrop:
            case TokenId::CompilerFuncMain:
            case TokenId::CompilerFuncPreMain:
                return true;

            default:
                return false;
        }
    }

    static bool isOpArithmetic(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpArithmetic); }
    static bool isOpBitwise(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpBitwise); }
    static bool isOpArithmeticOrBitwise(TokenId id) { return toKind(id).hasAny(TokenIdKindE::OpArithmetic | TokenIdKindE::OpBitwise); }
    static bool isOpEquality(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpEquality); }
    static bool isOpOrdering(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpOrdering); }
    // The operator token of a dereference unary node: the 'dref' keyword, or the '['
    // carried by the postfix place-deref 'expr[]'.
    static bool isDeref(TokenId id) { return id == TokenId::KwdDRef || id == TokenId::SymLeftBracket; }
    static bool isOpRelational(TokenId id) { return toKind(id).hasAny(TokenIdKindE::OpEquality | TokenIdKindE::OpOrdering); }
    static bool isOpLogical(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpLogical); }
    static bool isOpAssign(TokenId id) { return toKind(id).hasAll(TokenIdKindE::OpAssign); }
    static bool isOpCompoundAssign(TokenId id) { return isOpAssign(id) && id != TokenId::SymEqual; }

#if SWC_HAS_TOKEN_DEBUG_INFO
    const char8_t*  dbgPtr     = nullptr;
    SourceView*     dbgSrcView = nullptr;
    SourceCodeRange dbgLoc;
#endif
};

SWC_END_NAMESPACE();
