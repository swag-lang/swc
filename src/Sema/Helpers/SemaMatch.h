#pragma once
#include "Parser/AstVisitResult.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

class Symbol;
class Sema;
class LookUpContext;
class SymbolMap;

namespace SemaMatch
{
    AstVisitStepResult match(Sema& sema, LookUpContext& result, IdentifierRef idRef);
    AstVisitStepResult match(Sema& sema, const SymbolMap& symMa, LookUpContext& result, IdentifierRef idRef);
    AstVisitStepResult ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE()
