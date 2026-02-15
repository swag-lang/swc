#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

Result AstSuffixLiteral::semaPostNode(Sema& sema) const
{
    auto&              ctx        = sema.ctx();
    const SemaNodeView suffixView = sema.nodeView(nodeSuffixRef);
    const TypeRef      typeRef    = suffixView.typeRef;

    SemaNodeView nodeLiteralView = sema.nodeView(nodeLiteralRef);
    SWC_ASSERT(nodeLiteralView.cstRef.isValid());

    ConstantRef cstRef = nodeLiteralView.cstRef;

    // Special case for negation: we need to negate before casting, in order for -128's8 to compile, for example.
    // @MinusLiteralSuffix
    if (const auto parentNode = sema.visit().parentNode(); parentNode->is(AstNodeId::UnaryExpr))
    {
        const Token& tok = sema.token(parentNode->codeRef());
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
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cst.type(ctx).payloadIntBits(), TypeInfo::Sign::Signed));
            }
            else if (type.isFloat())
            {
                ApFloat cpy = cst.getFloat();
                cpy.negate();
                cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpy, cst.type(ctx).payloadFloatBits()));
            }
        }
    }

    nodeLiteralView.setCstRef(sema, cstRef);
    RESULT_VERIFY(Cast::cast(sema, nodeLiteralView, typeRef, CastKind::LiteralSuffix));
    sema.setConstant(sema.curNodeRef(), nodeLiteralView.cstRef);

    return Result::Continue;
}

Result AstCastExpr::semaPostNode(Sema& sema)
{
    if (hasFlag(AstCastExprFlagsE::Explicit))
    {
        const SemaNodeView nodeTypeView = sema.nodeView(nodeTypeRef);
        SemaNodeView       nodeExprView = sema.nodeView(nodeExprRef);

        // Value-check
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprView.nodeRef));

        // Check cast modifiers
        RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

        // Cast kind
        CastFlags castFlags = CastFlagsE::Zero;
        if (modifierFlags.has(AstModifierFlagsE::Bit))
            castFlags.add(CastFlagsE::BitCast);
        if (modifierFlags.has(AstModifierFlagsE::UnConst))
            castFlags.add(CastFlagsE::UnConst);

        RESULT_VERIFY(Cast::cast(sema, nodeExprView, nodeTypeView.typeRef, CastKind::Explicit, castFlags));
        sema.inheritPayload(*this, nodeExprView.nodeRef);
        sema.setIsValue(*this);
    }

    return Result::Continue;
}

Result AstAutoCastExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeExprView = sema.nodeView(nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprView.nodeRef));

    // Check cast modifiers
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst));

    // We do not know the destination type here (it comes from context).
    // Keep the node and inherit the child payload; the cast will be applied later.
    sema.inheritPayload(*this, nodeExprView.nodeRef);
    sema.setIsValue(*this);

    return Result::Continue;
}

SWC_END_NAMESPACE();
