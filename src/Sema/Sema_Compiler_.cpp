#include "pch.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(SemaJob& job, const AstNodeRef& childRef) const
{
    if (childRef == nodeCondition)
        return AstVisitStepResult::Continue;

    const auto nodeConditionPtr = job.node(nodeCondition);
    if (!nodeConditionPtr->isConstant())
    {
        job.raiseError(DiagnosticId::sema_err_expr_not_const, nodeCondition);
        return AstVisitStepResult::Continue;
    }

    const auto& constant = nodeConditionPtr->getConstant(job.ctx());
    if (!constant.isBool())
        return AstVisitStepResult::Stop;

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
