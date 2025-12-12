#include "pch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookupResult.h"
#include "Symbol/SymbolMap.h"
#include "Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void Sema::lookupIdentifier(LookupResult& result, IdentifierRef idRef) const
{
    result.clear();

    const SymbolMap* symMap = curScope_->symMap();
    while (symMap)
    {
        symMap->lookup(idRef, result.symbols());
        if (!result.empty())
            return;
        symMap = symMap->symMap();
    }

    semaInfo().fileNamespace().lookup(idRef, result.symbols());
    if (!result.empty())
        return;
}

SWC_END_NAMESPACE()
