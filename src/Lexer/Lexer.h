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

    const uint8_t* parseEol(const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end);
    const uint8_t* parseBlank(const LangSpec& langSpec, const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end);
    const uint8_t* parseSingleLineComment(const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end);
    const uint8_t* parseMultiLineComment(const CompilerInstance& ci, const CompilerContext& ctx, const uint8_t* buffer, const uint8_t* startBuffer, const uint8_t* end);

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }

    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
};
