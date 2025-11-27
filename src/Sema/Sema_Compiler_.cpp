#include "pch.h"
#include "Main/Global.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/ConstantValue.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeCondition)
        return AstVisitStepResult::Continue;

    const AstNode& nodeConditionPtr = sema.node(nodeCondition);
    if (!nodeConditionPtr.isSemaConstant())
    {
        sema.raiseError(DiagnosticId::sema_err_expr_not_const, nodeCondition);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeConditionPtr.getSemaConstant(sema.ctx());
    if (!constant.isBool())
    {
        sema.raiseInvalidType(nodeCondition, constant.typeRef(), sema.typeMgr().getTypeBool());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    const auto&    tok        = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeArgPtr = sema.node(nodeArg);

    if (!nodeArgPtr.isSemaConstant())
    {
        sema.raiseError(DiagnosticId::sema_err_expr_not_const, nodeArg);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeArgPtr.getSemaConstant(sema.ctx());

    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
            {
                sema.raiseInvalidType(nodeArg, constant.typeRef(), sema.typeMgr().getTypeString());
                return AstVisitStepResult::Stop;
            }
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
            {
                sema.raiseInvalidType(nodeArg, constant.typeRef(), sema.typeMgr().getTypeBool());
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
            auto diag = sema.reportError(DiagnosticId::sema_err_compiler_error, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = sema.reportError(DiagnosticId::sema_warn_compiler_warning, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const auto& ctx = sema.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString());
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
            {
                sema.raiseError(DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
                return AstVisitStepResult::Stop;
            }
            break;

        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
