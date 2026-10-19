#pragma once
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Lexer/Token.h"
#include "Support/Core/Flags.h"

SWC_BEGIN_NAMESPACE();

enum class DiagnosticId;
class Diagnostic;
class TaskContext;
class Global;
class SourceFile;
class LangSpec;

enum class LexerFlagsE : uint32_t
{
    Default                    = 0,
    RawMode                    = 1 << 0,
    EmitTrivia                 = 1 << 1,
    IgnoreGlobalCompilerIfSkip = 1 << 2,
    AllowReservedIdentifiers   = 1 << 3,
};
using LexerFlags = EnumFlags<LexerFlagsE>;

class Lexer
{
public:
    void tokenizeRaw(TaskContext& ctx, SourceView& srcView);
    void tokenize(TaskContext& ctx, SourceView& srcView, LexerFlags flags);

private:
    Token token_ = {};

    bool prevTokenWasWhitespace_ = false;
    bool prevTokenHadEolInside_  = false;

    // Track the last meaningful token on this line to distinguish quotes from
    // character literals. Trivia preserves it; a line break clears it.
    TokenId prevCodeTokenId_ = TokenId::Invalid;

    // #raw must be known before scanning the next string for its closing delimiter.
    bool pendingRawStringLiteral_ = false;

    SourceView* srcView_ = nullptr;

    const char8_t* buffer_      = nullptr;
    const char8_t* startBuffer_ = nullptr;
    const char8_t* endBuffer_   = nullptr;
    const char8_t* startToken_  = nullptr;

    TaskContext*    ctx_        = nullptr;
    const LangSpec* langSpec_   = nullptr;
    LexerFlags      lexerFlags_ = LexerFlagsE::Default;

    uint32_t startTokenOffset_ = 0;

    bool hasTokenError_ = false;
    bool hasFileError_  = false;
    bool hasUtf8Error_  = false;

    static bool isTerminatorAfterEscapeChar(uint8_t c, TokenId container);

    void eatOne();
    void eatOneEol();
    void eatUtf8Char();
    void pushToken();

    void       raiseUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    Diagnostic reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void       raiseTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);

    void checkFormat(uint32_t& startOffset);
    void checkGlobalCompilerIfSkip() const;
    void lexEscape(TokenId containerToken, bool eatEol);
    void buildTriviaIndex() const;

    bool isRawMode() const { return lexerFlags_.has(LexerFlagsE::RawMode); }

    void lexWhitespace();

    void lexSingleLineStringLiteral();
    void lexMultiLineStringLiteral();
    void lexCharacterLiteral();

    template<bool (LangSpec::*IsDigit)(uint32_t) const>
    uint32_t lexDigitRun(bool& ioLastWasSep);
    void     lexHexNumber();
    void     lexBinNumber();
    void     lexDecimalNumber();
    void     lexNumber();

    void lexSymbol();
    bool canPrecedeQuoteOperator() const;

    void lexIdentifier();

    void lexSingleLineComment();
    void lexMultiLineComment();
};

SWC_END_NAMESPACE();
