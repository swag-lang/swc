#pragma once
#include "Core/Flags.h"
#include "Lexer/Token.h"

enum class DiagnosticId;
class Diagnostic;
class CompilerContext;
class CompilerInstance;
class SourceFile;
class LangSpec;

using LexerFlags                                 = Flags<uint32_t>;
constexpr LexerFlags LEXER_DEFAULT               = 0x00000000;
constexpr LexerFlags LEXER_EXTRACT_COMMENTS_MODE = 0x00000001;

class Lexer
{
    Token token_ = {};

    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

    LexerFlags       lexerFlags_  = LEXER_DEFAULT;
    const uint8_t*   buffer_      = nullptr;
    const uint8_t*   end_         = nullptr;
    const uint8_t*   startBuffer_ = nullptr;
    CompilerContext* ctx_         = nullptr;
    const LangSpec*  langSpec_    = nullptr;

    void consumeOneEol();
    void pushToken();
    void reportError(DiagnosticId id, uint32_t offset, uint32_t len = 1) const;
    void checkFormat(const CompilerContext& ctx, uint32_t& startOffset) const;

    void parseEol();
    void parseBlank();
    void parseSingleLineStringLiteral();
    void parseMultiLineStringLiteral();
    void parseRawStringLiteral();
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

    Result tokenize(CompilerContext& ctx, LexerFlags flags = LEXER_DEFAULT);
};
