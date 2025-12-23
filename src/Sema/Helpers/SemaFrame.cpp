#include "pch.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

SymbolAccess SemaFrame::currentAccess(Sema& sema)
{
    return sema.frame().currentAccess();
}

SymbolMap* SemaFrame::currentSymMap(Sema& sema)
{
    const SymbolAccess access    = currentAccess(sema);
    SymbolMap*         symbolMap = sema.curSymMap();
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    return symbolMap;
}

SWC_END_NAMESPACE()
