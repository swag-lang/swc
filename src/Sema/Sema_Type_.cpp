#include "pch.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBuiltinType::semaPostNode(Sema& sema) const
{
    const auto&      tok     = sema.token(srcViewRef(), tokRef());
    const auto&      typeMgr = sema.typeMgr();
    auto&            semaCtx = sema.semaInfo();
    const AstNodeRef nodeRef = sema.curNodeRef();

    switch (tok.id)
    {
        case TokenId::TypeS8:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(8, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(16, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(32, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(64, false));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(8, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(16, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(32, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            semaCtx.setType(nodeRef, typeMgr.getTypeInt(64, true));
            return AstVisitStepResult::Continue;

        case TokenId::TypeF32:
            semaCtx.setType(nodeRef, typeMgr.getTypeFloat(32));
            return AstVisitStepResult::Continue;
        case TokenId::TypeF64:
            semaCtx.setType(nodeRef, typeMgr.getTypeFloat(64));
            return AstVisitStepResult::Continue;

        case TokenId::TypeBool:
            semaCtx.setType(nodeRef, typeMgr.getTypeBool());
            return AstVisitStepResult::Continue;
        case TokenId::TypeString:
            semaCtx.setType(nodeRef, typeMgr.getTypeString());
            return AstVisitStepResult::Continue;

        default:
            break;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    const auto&   ctx     = sema.ctx();
    const TypeRef typeRef = sema.typeRefOf(nodeSuffixRef);

    SWC_ASSERT(sema.hasConstant(nodeLiteralRef));

    CastContext castCtx;
    castCtx.kind         = CastKind::LiteralSuffix;
    castCtx.errorNodeRef = nodeLiteralRef;

    ConstantRef cstRef = sema.constantRefOf(nodeLiteralRef);

    // Special case for negation: we need to negate before casting, in order for -128's8 to compile, for example.
    // @MinusLiteralSuffix
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

    const ConstantRef newCstRef = sema.cast(castCtx, cstRef, typeRef);
    if (newCstRef.isInvalid())
        return AstVisitStepResult::Stop;
    sema.setConstant(sema.curNodeRef(), newCstRef);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
