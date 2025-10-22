#pragma once
#include "Lexer/Token.h"

enum class DiagnosticId;
class Diagnostic;
class CompilerContext;
class CompilerInstance;
class SourceFile;
class LangSpec;

enum class LexerFlagsEnum : uint32_t
{
    Default,
    ExtractCommentsMode,
};

using LexerFlags = Flags<LexerFlagsEnum>;

class Lexer
{
    Token token_     = {};
    Token prevToken_ = {};

    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

    LexerFlags       lexerFlags_    = LexerFlagsEnum::Default;
    const uint8_t*   buffer_        = nullptr;
    const uint8_t*   startBuffer_   = nullptr;
    const uint8_t*   endBuffer_     = nullptr;
    const uint8_t*   startToken_    = nullptr;
    CompilerContext* ctx_           = nullptr;
    const LangSpec*  langSpec_      = nullptr;
    bool             hasTokenError_ = false;
    bool             hasUtf8Error_  = false;

    void eatOneEol();
    void eatUtf8Char();
    void pushToken();
    void reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);
    void parseEscape(TokenId containerToken, bool eatEol);
    void checkFormat(const CompilerContext& ctx, uint32_t& startOffset);

    void parseEol();
    void parseBlank();
    void parseSingleLineStringLiteral();
    void parseMultiLineStringLiteral();
    void parseRawStringLiteral();
    void parseCharacterLiteral();
    void parseHexNumber();
    void parseBinNumber();
    void parseDecimalNumber();
    void parseNumber();
    void parseOperator();
    void parseIdentifier();
    void parseSingleLineComment();
    void parseMultiLineComment();

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }

    Result tokenize(CompilerContext& ctx, LexerFlags flags = LexerFlagsEnum::Default);
};
