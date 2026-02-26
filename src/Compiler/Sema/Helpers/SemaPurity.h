#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaPurity
{
    void computePurityFlag(Sema& sema, SymbolFunction& sym);
}

SWC_END_NAMESPACE();
