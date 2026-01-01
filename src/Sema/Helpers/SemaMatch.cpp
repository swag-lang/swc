#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"
#include "SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void lookup(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
    {
        lookUpCxt.symbols().clear();

        if (lookUpCxt.symMapHint)
        {
            lookUpCxt.symMapHint->lookupAppend(idRef, lookUpCxt);
        }
        else
        {
            const SymbolMap* symMap = sema.curScope().symMap();
            while (symMap)
            {
                symMap->lookupAppend(idRef, lookUpCxt);
                symMap = symMap->symMap();
            }

            sema.semaInfo().fileNamespace().lookupAppend(idRef, lookUpCxt);
        }
    }
}

AstVisitStepResult SemaMatch::match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
{
    lookup(sema, lookUpCxt, idRef);
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
    if (lookUpCxt.empty())
        return sema.waitIdentifier(sym.idRef(), sym.srcViewRef(), sym.tokRef());

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

    if (lookUpCxt.count() == 1)
        return AstVisitStepResult::Continue;

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        if (other->symMap() != sym.symMap())
            continue;
        SemaError::raiseAlreadyDefined(sema, &sym, other);
        return AstVisitStepResult::Stop;
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
