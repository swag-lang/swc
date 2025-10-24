#pragma once
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
    SourceFile* file_ = nullptr;
    Ast*        ast_  = nullptr;

public:
    Result parse(EvalContext& ctx);
};

SWC_END_NAMESPACE();
