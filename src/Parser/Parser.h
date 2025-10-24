#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class EvalContext;

class ParserOutput
{
protected:
    friend class Parser;
    Ast ast_;
};

class Parser
{
    SourceFile*  file_      = nullptr;
    Ast*         ast_       = nullptr;
    const Token* curToken_  = nullptr;
    const Token* lastToken_ = nullptr;

    void nextToken();

public:
    Result parse(EvalContext& ctx);
};

SWC_END_NAMESPACE();
