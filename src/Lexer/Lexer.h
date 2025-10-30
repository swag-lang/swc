#pragma once
#include "Core/StringMap.h"
#include "Core/Types.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE()

enum class DiagnosticId;
class Diagnostic;
class Context;
class Global;
class SourceFile;
class LangSpec;

enum class LexerFlags : uint32_t
{
    Default,
    ExtractTrivia, // Extract whitespace and comments as separate tokens
};
SWC_ENABLE_BITMASK(LexerFlags);

struct LexTrivia
{
    TokenRef tokenRef;
    Token    token;
};

struct LexIdentifier
{
    uint64_t hash      = 0;
    uint32_t byteStart = 0; // Byte offset in the source file buffer
};

class LexerOutput
{
protected:
    friend class Lexer;
    std::vector<Token>         tokens_;
    std::vector<LexTrivia>     trivia_;
    std::vector<uint32_t>      lines_;
    std::vector<LexIdentifier> identifiers_;

public:
    const std::vector<LexTrivia>&     trivia() const { return trivia_; }
    const std::vector<Token>&         tokens() const { return tokens_; }
    const std::vector<uint32_t>&      lines() const { return lines_; }
    const std::vector<LexIdentifier>& identifiers() const { return identifiers_; }
};

// Main lexer class - converts source text into tokens
class Lexer
{
    Token token_     = {};
    Token prevToken_ = {};

    SourceFile*     file_          = nullptr;
    LexerOutput*    lexOut_        = nullptr;
    LexerFlags      lexerFlags_    = LexerFlags::Default;
    const uint8_t*  buffer_        = nullptr;
    const uint8_t*  startBuffer_   = nullptr;
    const uint8_t*  endBuffer_     = nullptr;
    const uint8_t*  startToken_    = nullptr;
    Context*        ctx_           = nullptr;
    const LangSpec* langSpec_      = nullptr;
    bool            hasTokenError_ = false;
    bool            hasUtf8Error_  = false;
    bool            rawMode_       = false;

    static bool isTerminatorAfterEscapeChar(uint8_t c, TokenId container);

    void eatOneEol();
    void eatUtf8Char();
    void pushToken();
    void reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void checkFormat(const Context& ctx, uint32_t& startOffset);
    void lexEscape(TokenId containerToken, bool eatEol);

    void lexEol();
    void lexBlank();
    void lexSingleLineStringLiteral();
    void lexMultiLineStringLiteral();
    void lexRawStringLiteral();
    void lexCharacterLiteral();
    void lexHexNumber();
    void lexBinNumber();
    void lexDecimalNumber();
    void lexNumber();
    void lexOperator();
    void lexIdentifier();
    void lexSingleLineComment();
    void lexMultiLineComment();

public:
    Result tokenize(Context& ctx, LexerFlags flags = LexerFlags::Default);
    Result tokenizeRaw(Context& ctx);
};

SWC_END_NAMESPACE()
