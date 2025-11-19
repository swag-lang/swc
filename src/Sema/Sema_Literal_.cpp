#include "pch.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.visit().currentLex().token(tokValue);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
