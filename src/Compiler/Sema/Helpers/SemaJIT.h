#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaJIT
{
    Result runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef);
    Result runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef);
}

SWC_END_NAMESPACE();
