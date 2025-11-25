#include "pch.h"
#include "Main/Global.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/ConstantValue.h"
#include "Sema/SemaJob.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(SemaJob& job, const AstNodeRef& childRef) const
{
    if (childRef == nodeCondition)
        return AstVisitStepResult::Continue;

    const auto nodeConditionPtr = job.node(nodeCondition);
    if (!nodeConditionPtr->isSemaConstant())
    {
        job.raiseError(DiagnosticId::sema_err_expr_not_const, nodeCondition);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeConditionPtr->getSemaConstant(job.ctx());
    if (!constant.isBool())
    {
        job.raiseInvalidType(nodeCondition, job.typeMgr().getTypeBool(), constant.typeRef());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerFlow::semaPostNode(SemaJob& job) const
{
    const auto& tok        = job.token(srcViewRef(), tokRef());
    const auto  nodeArgPtr = job.node(nodeArg);

    if (!nodeArgPtr->isSemaConstant())
    {
        job.raiseError(DiagnosticId::sema_err_expr_not_const, nodeArg);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeArgPtr->getSemaConstant(job.ctx());

    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
            {
                job.raiseInvalidType(nodeArg, job.typeMgr().getTypeString(), constant.typeRef());
                return AstVisitStepResult::Stop;
            }
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
            {
                job.raiseInvalidType(nodeArg, job.typeMgr().getTypeBool(), constant.typeRef());
                return AstVisitStepResult::Stop;
            }
            break;

        default:
            break;
    }

    switch (tok.id)
    {
        case TokenId::CompilerError:
        {
            auto diag = job.reportError(DiagnosticId::sema_err_compiler_error, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(job.ctx());
            return AstVisitStepResult::Stop;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = job.reportError(DiagnosticId::sema_warn_compiler_warning, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(job.ctx());
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const auto& ctx = job.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString());
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
            {
                job.raiseError(DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
                return AstVisitStepResult::Stop;
            }
            break;

        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
