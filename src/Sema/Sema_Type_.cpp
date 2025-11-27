#include "pch.h"
#include "Parser/AstVisit.h"
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

        case TokenId::TypeF32:
            setSemaType(sema.typeMgr().getTypeFloat(32));
            return AstVisitStepResult::Continue;
        case TokenId::TypeF64:
            setSemaType(sema.typeMgr().getTypeFloat(64));
            return AstVisitStepResult::Continue;

        default:
            break;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstSuffixLiteral::semaPostNode(Sema& sema)
{
    auto&          ctx            = sema.ctx();
    auto&          cstMgr         = ctx.compiler().constMgr();
    const AstNode& nodeLiteralPtr = sema.node(nodeLiteralRef);
    const AstNode& nodeSuffixPtr  = sema.node(nodeSuffixRef);

    const TypeInfoRef type = nodeSuffixPtr.getNodeTypeRef(ctx);

    CastContext castCtx;
    castCtx.kind         = CastKind::LiteralSuffix;
    castCtx.errorNodeRef = nodeLiteralRef;

    const ConstantRef newCst = sema.cast(castCtx, nodeLiteralPtr.getSemaConstant(ctx), type);
    if (newCst.isInvalid())
        return AstVisitStepResult::Stop;

    setSemaConstant(newCst);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
