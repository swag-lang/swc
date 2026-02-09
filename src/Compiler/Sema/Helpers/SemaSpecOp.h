#pragma once
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

namespace SemaSpecOp
{
    Result validateSymbol(Sema& sema, SymbolFunction& sym);
    Result registerSymbol(Sema& sema, SymbolFunction& sym);
}

SWC_END_NAMESPACE();
