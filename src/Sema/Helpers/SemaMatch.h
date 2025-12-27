#pragma once
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class MatchResult;
class SymbolMap;

namespace SemaMatch
{
    void lookupAppend(Sema& sema, const SymbolMap& symMap, MatchResult& result, IdentifierRef idRef);
    void lookup(Sema& sema, MatchResult& result, IdentifierRef idRef);
    AstVisitStepResult ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE()
