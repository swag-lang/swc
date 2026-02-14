#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

struct AstCompilerRunExpr;
class Sema;

namespace SemaJit
{
    Result runExpr(Sema& sema, const AstCompilerRunExpr& node);
}

SWC_END_NAMESPACE();
