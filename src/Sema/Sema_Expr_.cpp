#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
