#pragma once
#include "Parser/AstVisitResult.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Symbol;
class Sema;
class MatchResult;
class SymbolMap;

namespace SemaMatch
{
    AstVisitStepResult match(Sema& sema, MatchResult& result, IdentifierRef idRef);
    AstVisitStepResult match(Sema& sema, const SymbolMap& symMa, MatchResult& result, IdentifierRef idRef);
    AstVisitStepResult ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE()
