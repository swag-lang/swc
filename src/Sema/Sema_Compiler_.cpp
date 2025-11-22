#include "pch.h"

#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"
#include "TypeManager.h"

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
    // if (!constant.isBool())
    {
        auto diag = job.reportError(DiagnosticId::sema_err_invalid_type, nodeCondition);
        diag.addArgument(Diagnostic::ARG_TYPE, job.typeMgr().toString(job.typeMgr().getBool()));
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, job.typeMgr().toString(constant.typeRef()));
        diag.report(job.ctx());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
