#pragma once
#include "Token.h"

class CompilerContext;
class CompilerInstance;
class SourceFile;

struct Lexer
{
    std::vector<Token>    tokens;
    std::vector<uint32_t> lines;

    Result tokenize(CompilerInstance& ci, const CompilerContext& ctx);
};
