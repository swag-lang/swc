#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/Cast.h"

SWC_BEGIN_NAMESPACE();

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
    RESULT_VERIFY(Cast::castConstant(sema, newCstRef, castCtx, cstRef, typeRef));
    sema.setConstant(sema.curNodeRef(), newCstRef);

    return Result::Continue;
}

Result AstExplicitCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));

    // Check cast modifiers
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // Cast kind
    CastFlags castFlags = CastFlagsE::Zero;
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);

    SemaNodeView nodeExprView(sema, nodeExprRef);
    RESULT_VERIFY(Cast::cast(sema, nodeExprView, nodeTypeView.typeRef, CastKind::Explicit, castFlags));
    sema.semaInherit(*this, nodeExprView.nodeRef);
    SemaInfo::setIsValue(*this);

    return Result::Continue;
}

SWC_END_NAMESPACE();
