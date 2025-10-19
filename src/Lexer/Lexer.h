#pragma once
#include "Token.h"

class CompilerContext;
class CompilerInstance;
class SourceFile;

class Lexer
{
    Token token_;

    std::vector<Token>    tokens_;
    std::vector<uint32_t> lines_;

public:
    const std::vector<Token>&    tokens() const { return tokens_; }
    const std::vector<uint32_t>& lines() const { return lines_; }

    Result tokenize(const CompilerInstance& ci, const CompilerContext& ctx);
};
