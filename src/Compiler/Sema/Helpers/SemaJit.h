#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstCompilerRunExpr;
class Sema;

namespace SemaJit
{
    Result runExpr(Sema& sema, AstNodeRef nodeExprRef);
}

SWC_END_NAMESPACE();
