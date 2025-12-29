#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"
#include "SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void lookupAppend(Sema&, const SymbolMap& symMap, LookUpContext& lookUpCxt, IdentifierRef idRef)
    {
        symMap.lookupAppend(idRef, lookUpCxt);
    }

    void lookup(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
    {
        lookUpCxt.symbols().clear();

        if (lookUpCxt.symMapHint)
        {
            lookupAppend(sema, *lookUpCxt.symMapHint, lookUpCxt, idRef);
        }
        else
        {
            const SymbolMap* symMap = sema.curScope().symMap();
            while (symMap)
            {
                lookupAppend(sema, *symMap, lookUpCxt, idRef);
                symMap = symMap->symMap();
            }

            lookupAppend(sema, sema.semaInfo().fileNamespace(), lookUpCxt, idRef);
        }
    }
}

AstVisitStepResult SemaMatch::match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
{
    lookup(sema, lookUpCxt, idRef);
    if (lookUpCxt.empty())
        return sema.waitIdentifier(idRef);

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other);
        if (!other->isComplete())
            return sema.waitComplete(other);
    }

    if (lookUpCxt.count() > 1)
    {
        SemaError::raiseAmbiguousSymbol(sema, lookUpCxt.srcViewRef, lookUpCxt.tokRef, lookUpCxt.symbols());
        return AstVisitStepResult::Stop;
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult SemaMatch::ghosting(Sema& sema, const Symbol& sym)
{
    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = sym.srcViewRef();
    lookUpCxt.tokRef     = sym.tokRef();

    lookup(sema, lookUpCxt, sym.idRef());
    SWC_ASSERT(!lookUpCxt.empty());

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other);
    }

    if (lookUpCxt.count() == 1)
        return AstVisitStepResult::Continue;

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;

        if (other->symMap() == sym.symMap())
        {
            SemaError::raiseAlreadyDefined(sema, &sym, other);
            return AstVisitStepResult::Stop;
        }
    }

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;

        SemaError::raiseGhosting(sema, &sym, other);
        return AstVisitStepResult::Stop;
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE()
