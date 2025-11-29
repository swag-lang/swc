#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstParenExpr::semaPostNode(Sema& sema)
{
    const auto node = sema.node(nodeExprRef);
    semaInherit(node);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
