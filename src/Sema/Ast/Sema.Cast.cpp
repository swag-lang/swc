#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

Result AstSuffixLiteral::semaPostNode(Sema& sema) const
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
                    return SemaError::raiseLiteralOverflow(sema, nodeLiteralRef, cst, cst.typeRef());
                cpy.setUnsigned(false);
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cst.type(ctx).intBits(), TypeInfo::Sign::Signed));
            }
            else if (type.isFloat())
            {
                ApFloat cpy = cst.getFloat();
                cpy.negate();
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpy, cst.type(ctx).floatBits()));
            }
        }
    }

    ConstantRef newCstRef;
    RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, cstRef, typeRef));
    sema.setConstant(sema.curNodeRef(), newCstRef);

    return Result::Continue;
}

Result AstExplicitCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValueExpr(sema, nodeExprRef));
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    // Check cast modifiers
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // Cast kind
    CastContext castCtx(CastKind::Explicit);
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castCtx.flags.add(CastFlagsE::BitCast);
    if (modifierFlags.has(AstModifierFlagsE::UnConst))
        castCtx.flags.add(CastFlagsE::UnConst);
    castCtx.errorNodeRef = nodeTypeView.nodeRef;

    // Update constant
    if (sema.hasConstant(nodeExprRef))
    {
        ConstantRef cstRef;
        RESULT_VERIFY(SemaCast::castConstant(sema, cstRef, castCtx, nodeExprView.cstRef, nodeTypeView.typeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    if (!SemaCast::castAllowed(sema, castCtx, nodeExprView.typeRef, nodeTypeView.typeRef))
        return SemaCast::emitCastFailure(sema, castCtx.failure);

    sema.setType(sema.curNodeRef(), nodeTypeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE()
