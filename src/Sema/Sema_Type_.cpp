#include "pch.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBuiltinType::semaPostNode(Sema& sema)
{
    const auto& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::TypeS8:
            setSemaType(sema.typeMgr().getTypeInt(8, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            setSemaType(sema.typeMgr().getTypeInt(16, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            setSemaType(sema.typeMgr().getTypeInt(32, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            setSemaType(sema.typeMgr().getTypeInt(64, true));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            setSemaType(sema.typeMgr().getTypeInt(8, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            setSemaType(sema.typeMgr().getTypeInt(16, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            setSemaType(sema.typeMgr().getTypeInt(32, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            setSemaType(sema.typeMgr().getTypeInt(64, false));
            return AstVisitStepResult::Continue;

        default:
            break;
    }

    sema.raiseInternalError(this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstSuffixLiteral::semaPostNode(Sema& sema)
{
    auto&          ctx            = sema.ctx();
    auto&          cstMgr         = ctx.compiler().constMgr();
    const AstNode& nodeLiteralPtr = sema.node(nodeLiteral);
    const AstNode& nodeSuffixPtr  = sema.node(nodeSuffix);

    const TypeInfoRef type     = nodeSuffixPtr.getNodeTypeRef(ctx);
    bool              overflow = false;
    const ConstantRef newCst   = sema.convert(nodeLiteralPtr.getSemaConstant(ctx), type, overflow);
    if (overflow)
    {
        auto diag = sema.reportError(DiagnosticId::sema_err_literal_overflow, nodeLiteralPtr.srcViewRef(), nodeLiteralPtr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, type);
        diag.report(ctx);
        return AstVisitStepResult::Stop;
    }

    setSemaConstant(newCst);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
