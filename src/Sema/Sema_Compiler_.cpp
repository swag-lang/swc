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
    if (!constant.isBool())
    {
        auto diag = job.reportError(DiagnosticId::sema_err_invalid_type, nodeCondition);
        diag.addArgument(Diagnostic::ARG_TYPE, job.typeMgr().toName(constant.typeRef()));
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, job.typeMgr().toName(job.typeMgr().getBool()));
        diag.report(job.ctx());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerCallUnary::semaPostNode(SemaJob& job) const
{
    const auto& tok     = job.token(srcViewRef(), tokRef());
    const auto  nodeArg = job.node(nodeArg1);

    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
        case TokenId::CompilerPrint:
        {
            if (!nodeArg->isConstant())
            {
                job.raiseError(DiagnosticId::sema_err_expr_not_const, nodeArg1);
                return AstVisitStepResult::Continue;
            }

            const auto& constant = nodeArg->getConstant(job.ctx());
            if (!constant.isString())
            {
                auto diag = job.reportError(DiagnosticId::sema_err_invalid_type, nodeArg1);
                diag.addArgument(Diagnostic::ARG_TYPE, job.typeMgr().toName(constant.typeRef()));
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, job.typeMgr().toName(job.typeMgr().getString()));
                diag.report(job.ctx());
                return AstVisitStepResult::Stop;
            }
            break;
        }

        default:
            break;
    }

    switch (tok.id)
    {
        case TokenId::CompilerError:
        {
            const auto diag = job.reportError(DiagnosticId::cmd_err_no_input, srcViewRef(), tokRef());
            diag.report(job.ctx());
            break;
        }

        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
