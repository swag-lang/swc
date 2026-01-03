#include "pch.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void collect(Sema& sema, LookUpContext& lookUpCxt)
    {
        lookUpCxt.symMaps.clear();

        if (lookUpCxt.symMapHint)
        {
            lookUpCxt.symMaps.push_back(lookUpCxt.symMapHint);
        }
        else
        {
            const SemaScope* scope = &sema.curScope();
            while (scope)
            {
                if (const auto* symMap = scope->symMap())
                    lookUpCxt.symMaps.push_back(symMap);
                for (const auto* usingSymMap : scope->usingSymMaps())
                    lookUpCxt.symMaps.push_back(usingSymMap);
                scope = scope->parent();
            }

            lookUpCxt.symMaps.push_back(&sema.semaInfo().fileNamespace());
            lookUpCxt.symMaps.push_back(&sema.semaInfo().moduleNamespace());
        }
    }

    void lookup(LookUpContext& lookUpCxt, IdentifierRef idRef)
    {
        lookUpCxt.symbols().clear();
        for (const auto* symMap : lookUpCxt.symMaps)
        {
            symMap->lookupAppend(idRef, lookUpCxt);
        }
    }
}

Result SemaMatch::match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
{
    collect(sema, lookUpCxt);
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
        return sema.waitIdentifier(idRef, lookUpCxt.srcViewRef, lookUpCxt.tokRef);

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
        if (!other->isTyped())
            return sema.waitTyped(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

    if (lookUpCxt.count() > 1)
        return SemaError::raiseAmbiguousSymbol(sema, lookUpCxt.srcViewRef, lookUpCxt.tokRef, lookUpCxt.symbols());

    return Result::Continue;
}

Result SemaMatch::ghosting(Sema& sema, const Symbol& sym)
{
    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = sym.srcViewRef();
    lookUpCxt.tokRef     = sym.tokRef();

    collect(sema, lookUpCxt);
    lookup(lookUpCxt, sym.idRef());
    if (lookUpCxt.empty())
        return sema.waitIdentifier(sym.idRef(), sym.srcViewRef(), sym.tokRef());

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

    if (lookUpCxt.count() == 1)
        return Result::Continue;

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        if (other->symMap() != sym.symMap())
            continue;
        return SemaError::raiseAlreadyDefined(sema, &sym, other);
    }

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        return SemaError::raiseGhosting(sema, &sym, other);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE()
