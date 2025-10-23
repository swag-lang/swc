#pragma once
#include "Lexer/Token.h"

enum class DiagnosticId;
class Diagnostic;
class CompilerContext;
class Global;
class SourceFile;
class LangSpec;

enum class LexerFlagsEnum : uint32_t
{
    Default,
    ExtractBlanks,
    ExtractEols,
    ExtractComments,
};

using LexerFlags = Flags<LexerFlagsEnum>;

class LexerOutput
{
protected:
    friend class Lexer;
    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }
};

class Lexer
{
    Token token_     = {};
    Token prevToken_ = {};

    SourceFile*      file_          = nullptr;
    LexerFlags       lexerFlags_    = LexerFlagsEnum::Default;
    const uint8_t*   buffer_        = nullptr;
    const uint8_t*   startBuffer_   = nullptr;
    const uint8_t*   endBuffer_     = nullptr;
    const uint8_t*   startToken_    = nullptr;
    CompilerContext* ctx_           = nullptr;
    const LangSpec*  langSpec_      = nullptr;
    bool             hasTokenError_ = false;
    bool             hasUtf8Error_  = false;
    bool             rawMode_       = false;

    void eatOneEol();
    void eatUtf8Char();
    void pushToken();
    void reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void checkFormat(const CompilerContext& ctx, uint32_t& startOffset);
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
    Result tokenize(CompilerContext& ctx, LexerFlags flags = LexerFlagsEnum::Default);
    Result tokenizeRaw(CompilerContext& ctx);
};
