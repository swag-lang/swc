#include "pch.h"
#include "Constant/ConstantManager.h"
#include "Sema/Helpers/SemaCast.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    const auto&   ctx     = sema.ctx();
    const TypeRef typeRef = sema.typeRefOf(nodeSuffixRef);

    SWC_ASSERT(sema.hasConstant(nodeLiteralRef));

    CastContext castCtx(CastKind::LiteralSuffix);
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
                    sema.raiseLiteralOverflow(nodeLiteralRef, cst, cst.typeRef());
                    return AstVisitStepResult::Stop;
                }

                cpy.setUnsigned(false);
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cst.type(ctx).intBits()));
            }
            else if (type.isFloat())
            {
                ApFloat cpy = cst.getFloat();
                cpy.negate();
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpy, cst.type(ctx).floatBits()));
            }
        }
    }

    const ConstantRef newCstRef = SemaCast::castConstant(sema, castCtx, cstRef, typeRef);
    if (newCstRef.isInvalid())
        return AstVisitStepResult::Stop;
    sema.setConstant(sema.curNodeRef(), newCstRef);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstExplicitCastExpr::semaPostNode(Sema& sema) const
{
    if (sema.checkModifiers(*this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst) == Result::Error)
        return AstVisitStepResult::Stop;

    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    CastContext castCtx(CastKind::Explicit);
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castCtx.flags.add(CastFlagsE::BitCast);
    castCtx.errorNodeRef = nodeTypeView.nodeRef;

    if (sema.hasConstant(nodeExprRef))
    {
        const ConstantRef cstRef = SemaCast::castConstant(sema, castCtx, nodeExprView.cstRef, nodeTypeView.typeRef);
        if (cstRef.isInvalid())
            return AstVisitStepResult::Stop;
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    if (!SemaCast::castAllowed(sema, castCtx, nodeExprView.typeRef, nodeTypeView.typeRef))
        return AstVisitStepResult::Stop;

    sema.setType(sema.curNodeRef(), nodeTypeView.typeRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
