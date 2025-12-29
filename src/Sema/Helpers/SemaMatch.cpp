#include "pch.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/MatchResult.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"
#include "SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void lookupAppend(Sema&, const SymbolMap& symMap, MatchResult& result, IdentifierRef idRef)
    {
        symMap.lookupAppend(idRef, result.symbols());
    }

    void lookup(Sema& sema, MatchResult& result, IdentifierRef idRef)
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
}

AstVisitStepResult SemaMatch::match(Sema& sema, MatchResult& result, IdentifierRef idRef)
{
    lookup(sema, result, idRef);

    if (result.empty())
    {
        return sema.waitIdentifier(idRef);
    }

    for (const Symbol* other : result.symbols())
    {
        if (!other->isDeclared() || !other->isComplete())
        {
            return sema.waitComplete(other);
        }
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult SemaMatch::match(Sema& sema, const SymbolMap& symMap, MatchResult& result, IdentifierRef idRef)
{
    lookupAppend(sema, symMap, result, idRef);
    if (result.empty())
        return sema.waitIdentifier(idRef);

    for (const Symbol* other : result.symbols())
    {
        if (!other->isDeclared() || !other->isComplete())
        {
            return sema.waitComplete(other);
        }
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult SemaMatch::ghosting(Sema& sema, const Symbol& sym)
{
    MatchResult result;
    lookup(sema, result, sym.idRef());

    SWC_ASSERT(!result.empty());
    if (result.count() == 1)
        return AstVisitStepResult::Continue;

    for (const Symbol* other : result.symbols())
    {
        if (!other->isDeclared())
        {
            return sema.waitDeclared();
        }
    }

    for (const Symbol* other : result.symbols())
    {
        if (other == &sym)
            continue;
        SemaError::raiseSymbolAlreadyDefined(sema, &sym, other);
        return AstVisitStepResult::Stop;
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE()
