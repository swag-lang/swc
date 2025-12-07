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
    const AstNodeRef nodeRef = sema.curNodeRef();

    switch (tok.id)
    {
        case TokenId::TypeS8:
            sema.setType(nodeRef, typeMgr.getTypeInt(8, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, false));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            sema.setType(nodeRef, typeMgr.getTypeInt(8, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, true));
            return AstVisitStepResult::Continue;

        case TokenId::TypeF32:
            sema.setType(nodeRef, typeMgr.getTypeFloat(32));
            return AstVisitStepResult::Continue;
        case TokenId::TypeF64:
            sema.setType(nodeRef, typeMgr.getTypeFloat(64));
            return AstVisitStepResult::Continue;

        case TokenId::TypeBool:
            sema.setType(nodeRef, typeMgr.getTypeBool());
            return AstVisitStepResult::Continue;
        case TokenId::TypeString:
            sema.setType(nodeRef, typeMgr.getTypeString());
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
        const Token& tok = sema.token(parentNode->srcViewRef(), parentNode->tokRef());
        if (tok.is(TokenId::SymMinus))
        {
            const ConstantValue& cst  = sema.cstMgr().get(cstRef);
            const TypeInfo&      type = sema.typeMgr().get(cst.typeRef());
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
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, 0));
            }
        }
    }

    const ConstantRef newCstRef = sema.cast(castCtx, cstRef, typeRef);
    if (newCstRef.isInvalid())
        return AstVisitStepResult::Stop;
    sema.setConstant(sema.curNodeRef(), newCstRef);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstValueType::semaPostNode(Sema& sema) const
{
    auto&               ctx     = sema.ctx();
    const TypeRef       typeRef = sema.typeRefOf(nodeTypeRef);
    const ConstantValue cst     = ConstantValue::makeTypeInfo(ctx, typeRef);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cst));
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
