#include "pch.h"
#include "SemaError.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/MatchResult.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

void SemaMatch::lookupAppend(Sema&, const SymbolMap& symMap, MatchResult& result, IdentifierRef idRef)
{
    symMap.lookupAppend(idRef, result.symbols());
}

void SemaMatch::lookup(Sema& sema, MatchResult& result, IdentifierRef idRef)
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
            sema.pause(TaskStateKind::SemaWaitingComplete);
            return AstVisitStepResult::Pause;
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
