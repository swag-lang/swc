#pragma once
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace SemaDeclGhost
{
    template<typename T>
    inline Result run(Sema& sema, const T& node)
    {
        if (sema.enteringState())
            SemaHelpers::declareSymbol(sema, node);
        const Symbol& sym = *sema.curViewSymbol().sym();
        return Match::ghosting(sema, sym);
    }
}

SWC_END_NAMESPACE();
