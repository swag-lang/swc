#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstCompilerRunExpr;
class Sema;

namespace SemaJIT
{
    Result runExpr(Sema& sema, AstNodeRef nodeRunExprRef, AstNodeRef nodeExprRef);
}

SWC_END_NAMESPACE();
