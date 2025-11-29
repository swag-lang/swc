#include "pch.h"
#include "Main/Global.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/ConstantValue.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return AstVisitStepResult::Continue;

    const AstNode& nodeCondition = sema.node(nodeConditionRef);
    if (!nodeCondition.isSemaConstant())
    {
        sema.raiseExprNotConst(nodeConditionRef);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeCondition.getSemaConstant(sema.ctx());
    if (!constant.isBool())
    {
        sema.raiseInvalidType(nodeConditionRef, constant.typeRef(), sema.typeMgr().getTypeBool());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlockRef && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlockRef && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    const auto&    tok     = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeArg = sema.node(nodeArgRef);

    if (!nodeArg.isSemaConstant())
    {
        sema.raiseExprNotConst(nodeArgRef);
        return AstVisitStepResult::Stop;
    }

    const auto& constant = nodeArg.getSemaConstant(sema.ctx());

    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
            {
                sema.raiseInvalidType(nodeArgRef, constant.typeRef(), sema.typeMgr().getTypeString());
                return AstVisitStepResult::Stop;
            }
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
            {
                sema.raiseInvalidType(nodeArgRef, constant.typeRef(), sema.typeMgr().getTypeBool());
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
