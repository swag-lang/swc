#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.SpecOpKind.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

namespace SemaSpecOp
{
    SpecOpKind computeSymbolKind(const Sema& sema, const SymbolFunction& sym);
    Result validateSymbol(Sema& sema, SymbolFunction& sym);
    Result registerSymbol(Sema& sema, SymbolFunction& sym);
}

SWC_END_NAMESPACE();
