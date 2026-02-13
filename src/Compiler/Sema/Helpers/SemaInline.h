#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaInline
{
    bool   isFunctionPureFromAst(Sema& sema, const SymbolFunction& fn);
    bool   canInlineCall(Sema& sema, const SymbolFunction& fn);
    Result tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
}

SWC_END_NAMESPACE();
