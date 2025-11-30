#pragma once
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class SemaContext
{
    Ast ast_;

public:
    Ast&       ast() { return ast_; }
    const Ast& ast() const { return ast_; }
};

SWC_END_NAMESPACE()
