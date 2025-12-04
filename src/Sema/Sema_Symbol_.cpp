#include "pch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookupResult.h"
#include "Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

void Sema::lookupIdentifier(LookupResult& result, IdentifierRef idRef)
{
    result.clear();

    const SymbolMap* symMap = curScope_->symMap();
    while (symMap)
    {
        symMap->lookup(idRef, result.symbols());
        if (!result.empty())
            break;
        symMap = symMap->symMap();
    }
}

SWC_END_NAMESPACE()
