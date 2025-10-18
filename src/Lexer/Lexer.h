#pragma once
#include "Token.h"

class CompilerContext;
class CompilerInstance;
class SourceFile;

class Lexer
{
    std::vector<Token> tokens_;
    
public:
    Result tokenize(CompilerInstance& ci, const CompilerContext& ctx);
};
