#include "pch.h"

#include "SemaError.h"
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

LookUpReturn SemaMatch::ghosting(Sema& sema, Symbol& sym, IdentifierRef idRef)
{
    LookupResult result;
    lookup(sema, result, sym.idRef());
    SWC_ASSERT(!result.empty());
    if (result.count() == 1)
        return LookUpReturn::Success;
    
    for (const Symbol* other : result.symbols())
    {
        if (other == &sym)
            continue;
        SemaError::raiseSymbolAlreadyDefined(sema, &sym, other);
        return LookUpReturn::Error;
    }
    
    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE()
