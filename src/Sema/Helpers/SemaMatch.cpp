#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookupResult.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void SemaMatch::lookupAppend(Sema&, const SymbolMap& symMap, LookupResult& result, IdentifierRef idRef)
{
    symMap.lookupAppend(idRef, result.symbols());
}

void SemaMatch::lookup(Sema& sema, LookupResult& result, IdentifierRef idRef)
{
    result.clear();

    const SymbolMap* symMap = sema.curScope().symMap();
    while (symMap)
    {
        lookupAppend(sema, *symMap, result, idRef);
        symMap = symMap->symMap();
    }

    lookupAppend(sema, sema.semaInfo().fileNamespace(), result, idRef);
}

SWC_END_NAMESPACE()
