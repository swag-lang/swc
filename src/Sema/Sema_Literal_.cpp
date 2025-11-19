#include "pch.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
