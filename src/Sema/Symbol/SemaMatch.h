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
    AstStepResult match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef);
    AstStepResult ghosting(Sema& sema, const Symbol& sym);
}

SWC_END_NAMESPACE()
