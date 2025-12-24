#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookupResult.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void SemaMatch::lookup(Sema&, const SymbolMap& symMap, LookupResult& result, IdentifierRef idRef)
{
    symMap.lookup(idRef, result.symbols());
}

void SemaMatch::lookup(Sema& sema, LookupResult& result, IdentifierRef idRef)
{
    result.clear();

    const SymbolMap* symMap = sema.curScope().symMap();
    while (symMap)
    {
        lookup(sema, *symMap, result, idRef);
        if (!result.empty())
            break;
        symMap = symMap->symMap();
    }

    if (result.empty())
    {
        lookup(sema, sema.semaInfo().fileNamespace(), result, idRef);
    }
}

SWC_END_NAMESPACE()
