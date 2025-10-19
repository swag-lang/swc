#pragma once
#include "Token.h"

class CompilerContext;
class CompilerInstance;
class SourceFile;
class LangSpec;

class Lexer
{
    Token token_;

    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

    const uint8_t*          buffer_      = nullptr;
    const uint8_t*          end_         = nullptr;
    const uint8_t*          startBuffer_ = nullptr;
    const CompilerInstance* ci_          = nullptr;
    const CompilerContext*  ctx_         = nullptr;
    const LangSpec*         langSpec_    = nullptr;

    void consumeOneEol();

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

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }

    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
};
