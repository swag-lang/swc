#pragma once
#include "Lexer/SourceView.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

enum class DiagnosticId;
class Diagnostic;
class TaskContext;
class Global;
class SourceFile;
class LangSpec;

enum class LexerFlagsE : uint32_t
{
    Default,
    RawMode,
    EmitTrivia,
};
using LexerFlags = EnumFlags<LexerFlagsE>;

// Main lexer class - converts source text into tokens
class Lexer
{
public:
    void tokenizeRaw(TaskContext& ctx, SourceView& srcView);
    void tokenize(TaskContext& ctx, SourceView& srcView, LexerFlags flags);

private:
    Token token_     = {};
    Token prevToken_ = {};

    SourceView*     srcView_          = nullptr;
    const char8_t*  buffer_           = nullptr;
    const char8_t*  startBuffer_      = nullptr;
    const char8_t*  endBuffer_        = nullptr;
    const char8_t*  startToken_       = nullptr;
    TaskContext*    ctx_              = nullptr;
    const LangSpec* langSpec_         = nullptr;
    LexerFlags      lexerFlags_       = LexerFlagsE::Default;
    uint32_t        startTokenOffset_ = 0;
    bool            hasTokenError_    = false;
    bool            hasUtf8Error_     = false;

    static bool isTerminatorAfterEscapeChar(uint8_t c, TokenId container);

    void       eatOne();
    void       eatOneEol();
    void       eatUtf8Char();
    void       pushToken();
    void       raiseUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    Diagnostic reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void       raiseTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void       checkFormat(uint32_t& startOffset);
    void       lexEscape(TokenId containerToken, bool eatEol);
    void       buildTriviaIndex() const;

    bool isRawMode() const { return lexerFlags_.has(LexerFlagsE::RawMode); }

    void lexWhitespace();
    void lexSingleLineStringLiteral();
    void lexMultiLineStringLiteral();
    void lexRawStringLiteral();
    void lexCharacterLiteral();
    void lexHexNumber();
    void lexBinNumber();
    void lexDecimalNumber();
    void lexNumber();
    void lexSymbol();
    void lexIdentifier();
    void lexSingleLineComment();
    void lexMultiLineComment();
};

SWC_END_NAMESPACE();
