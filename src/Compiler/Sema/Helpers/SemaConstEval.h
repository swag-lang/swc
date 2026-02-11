#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

struct SemaConstEval
{
    static Result tryConstantFoldPureCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
};

SWC_END_NAMESPACE();
