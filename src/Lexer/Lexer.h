#pragma once
#include "Core/Flags.h"
#include "Lexer/Token.h"

class Diagnostic;
class CompilerContext;
class CompilerInstance;
class SourceFile;
class LangSpec;

using LexerFlags                    = Flags<uint32_t>;
constexpr LexerFlags LEXER_DEFAULT  = 0x00000000;
constexpr LexerFlags LEXER_EXTRACT_COMMENTS_MODE = 0x00000001;

class Lexer
{
    Token token_ = {};

    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

    LexerFlags              lexerFlags_  = LEXER_DEFAULT;
    const uint8_t*          buffer_      = nullptr;
    const uint8_t*          end_         = nullptr;
    const uint8_t*          startBuffer_ = nullptr;
    const CompilerInstance* ci_          = nullptr;
    const CompilerContext*  ctx_         = nullptr;
    const LangSpec*         langSpec_    = nullptr;

    void   consumeOneEol();
    void   pushToken();
    Result reportError(const Diagnostic& diag) const;

    Result parseEol();
    Result parseBlank();
    Result parseSingleLineStringLiteral();
    Result parseMultiLineStringLiteral();
    Result parseRawStringLiteral();
    Result parseHexNumber();
    Result parseBinNumber();
    Result parseNumber();
    Result parseSingleLineComment();
    Result parseMultiLineComment();

    static Result checkFormat(const CompilerInstance& ci, const CompilerContext& ctx, uint32_t& startOffset);

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }

    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx, LexerFlags flags = LEXER_DEFAULT);
};
