#include "pch.h"

#include "ConstantManager.h"
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
            setSemaType(sema.typeMgr().getTypeInt(8, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            setSemaType(sema.typeMgr().getTypeInt(16, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            setSemaType(sema.typeMgr().getTypeInt(32, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            setSemaType(sema.typeMgr().getTypeInt(64, false));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            setSemaType(sema.typeMgr().getTypeInt(8, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            setSemaType(sema.typeMgr().getTypeInt(16, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            setSemaType(sema.typeMgr().getTypeInt(32, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            setSemaType(sema.typeMgr().getTypeInt(64, true));
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
    auto&             ctx         = sema.ctx();
    const AstNode&    nodeLiteral = sema.node(nodeLiteralRef);
    const AstNode&    nodeSuffix  = sema.node(nodeSuffixRef);
    const TypeInfoRef typeRef     = nodeSuffix.getNodeTypeRef(ctx);

    SWC_ASSERT(nodeLiteral.isSemaConstant());

    CastContext castCtx;
    castCtx.kind         = CastKind::LiteralSuffix;
    castCtx.errorNodeRef = nodeLiteralRef;

    auto cstRef = nodeLiteral.getSemaConstantRef();

    // Special case for negation: we need to negate before casting, in order for -128's8 to compile for example
    if (const auto parentNode = sema.visit().parentNode(); parentNode->is(AstNodeId::UnaryExpr))
    {
        const auto tok = sema.token(parentNode->srcViewRef(), parentNode->tokRef());
        if (tok.is(TokenId::SymMinus))
        {
            const auto& cst  = sema.constMgr().get(cstRef);
            const auto  type = sema.typeMgr().get(cst.typeRef());
            if (type.isInt())
            {
                ApsInt cpy = cst.getInt();

                bool overflow = false;
                cpy.negate(overflow);
                if (overflow)
                {
                    sema.raiseLiteralOverflow(nodeLiteralRef, cst.typeRef());
                    return AstVisitStepResult::Stop;
                }

                cpy.setUnsigned(false);
                cstRef = sema.constMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, 0));
            }
        }
    }

    const ConstantRef newCstRef = sema.cast(castCtx, sema.constMgr().get(cstRef), typeRef);
    if (newCstRef.isInvalid())
        return AstVisitStepResult::Stop;
    setSemaConstant(newCstRef);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
