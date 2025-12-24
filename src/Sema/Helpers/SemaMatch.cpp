#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookupResult.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void SemaMatch::lookup(Sema& sema, LookupResult& result, IdentifierRef idRef)
{
    result.clear();

    const SymbolMap* symMap = sema.curScope().symMap();
    while (symMap)
    {
        symMap->lookup(idRef, result.symbols());
        if (!result.empty())
            break;
        symMap = symMap->symMap();
    }

    if (result.empty())
        sema.semaInfo().fileNamespace().lookup(idRef, result.symbols());
}

SWC_END_NAMESPACE()
