#include "pch.h"
#include "Math/Helpers.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaNodeView.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef bitCastConstant(Sema& sema, const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef)
    {
        auto&                ctx        = sema.ctx();
        const TypeManager&   typeMgr    = ctx.typeMgr();
        const ConstantValue& src        = sema.cstMgr().get(srcRef);
        const TypeInfo&      srcType    = typeMgr.get(src.typeRef());
        const TypeInfo&      targetType = typeMgr.get(targetTypeRef);

        // Only numeric bit-casts for now (int-like / float).
        const bool srcInt   = srcType.isIntLike();
        const bool srcFloat = srcType.isFloat();
        const bool dstInt   = targetType.isIntLike();
        const bool dstFloat = targetType.isFloat();

        if ((!srcInt && !srcFloat) || (!dstInt && !dstFloat))
        {
            sema.raiseCannotCast(castCtx.errorNodeRef, src.typeRef(), targetTypeRef);
            return ConstantRef::invalid();
        }

        const uint32_t srcBits = srcInt ? srcType.intLikeBits() : srcType.floatBits();
        const uint32_t dstBits = dstInt ? targetType.intLikeBits() : targetType.floatBits();

        // bit cast requires the same size.
        if (srcBits == 0 || dstBits == 0 || srcBits != dstBits)
        {
            sema.raiseCannotCast(castCtx.errorNodeRef, src.typeRef(), targetTypeRef);
            return ConstantRef::invalid();
        }

        // int-like -> int-like (same width): just re-tag signedness, do NOT change the underlying bit pattern.
        if (srcInt && dstInt)
        {
            ApsInt value = src.getIntLike();

            // Only change the signed/unsigned *interpretation*; bitWidth already matches.
            if (value.isUnsigned() != targetType.isIntLikeUnsigned())
                value.setUnsigned(targetType.isIntLikeUnsigned());

            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
            return ctx.cstMgr().addConstant(ctx, result);
        }

        // float -> float, same width: value is already that format.
        if (srcFloat && dstFloat)
        {
            const ApFloat&      value  = src.getFloat();
            const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
            return ctx.cstMgr().addConstant(ctx, result);
        }

        // float <-> int-like, same width: reinterpret raw bits.
        if (srcFloat && dstInt)
        {
            ApsInt              i      = Math::bitCastToApInt(src.getFloat());
            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, targetType);
            return ctx.cstMgr().addConstant(ctx, result);
        }

        if (srcInt && dstFloat)
        {
            ApFloat             f      = Math::bitCastToApFloat(src.getIntLike(), dstBits);
            const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
            return ctx.cstMgr().addConstant(ctx, result);
        }

        sema.raiseCannotCast(castCtx.errorNodeRef, src.typeRef(), targetTypeRef);
        return ConstantRef::invalid();
    }

    ConstantRef castIntLikeToIntLike(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

        // Working copy of the integer value (with SOURCE signedness)
        ApsInt value = src.getIntLike();

        const uint32_t targetBits     = targetType.intLikeBits();
        const bool     targetUnsigned = targetType.isIntLikeUnsigned();
        const uint32_t valueBits      = value.bitWidth();

        // We’ll use a width large enough to express both source and target safely.
        const uint32_t checkBits = (valueBits > targetBits + 1) ? valueBits : (targetBits + 1);

        bool overflow = false;

        // Unsigned target: [0, 2^N - 1]
        if (targetUnsigned)
        {
            // Negative signed source can never fit.
            if (!value.isUnsigned() && value.isNegative())
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_signed_unsigned, castCtx.errorNodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
                diag.report(ctx);
                return ConstantRef::invalid();
            }

            // Compare in UNSIGNED space.
            ApsInt vCheck = value;
            if (!vCheck.isUnsigned())
                vCheck.setUnsigned(true);

            vCheck.resize(checkBits);

            ApsInt maxCheck = ApsInt::maxValue(targetBits, true);
            maxCheck.resize(checkBits);

            if (vCheck.gt(maxCheck))
                overflow = true;
        }

        // Signed target: [-(2^(N-1)), 2^(N-1) - 1]
        else
        {
            ApsInt minSigned = ApsInt::minValue(targetBits, false);
            ApsInt maxSigned = ApsInt::maxValue(targetBits, false);

            if (!value.isUnsigned())
            {
                // Signed source: do signed comparison in a widened signed type.
                ApsInt vCheck = value;
                if (vCheck.isUnsigned())
                    vCheck.setUnsigned(false);
                vCheck.resize(checkBits); // sign-extend

                ApsInt minCheck = minSigned;
                ApsInt maxCheck = maxSigned;
                minCheck.resize(checkBits);
                maxCheck.resize(checkBits);

                if (vCheck.lt(minCheck) || vCheck.gt(maxCheck))
                    overflow = true;
            }
            else
            {
                // Unsigned source into signed target.
                // Lower bound (>= 0) is always OK, so only check the upper bound.

                // Compare in UNSIGNED space against maxSigned interpreted as unsigned.
                ApsInt vCheck = value;
                if (!vCheck.isUnsigned())
                    vCheck.setUnsigned(true);
                vCheck.resize(checkBits); // zero-extend

                ApsInt maxU = maxSigned;
                if (!maxU.isUnsigned())
                    maxU.setUnsigned(true); // reinterpret bits as unsigned
                maxU.resize(checkBits);     // zero-extend

                if (vCheck.gt(maxU))
                    overflow = true;
            }
        }

        if (overflow)
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, targetTypeRef);
            return ConstantRef::invalid();
        }

        // Adjust signedness to target
        if (value.isUnsigned() != targetUnsigned)
            value.setUnsigned(targetUnsigned);

        // Resize to the target bit width (now safe; we already checked range)
        value.resize(targetBits);

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castIntLikeToFloat(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
        const ApsInt       intVal     = src.getIntLike();
        const uint32_t     targetBits = targetType.floatBits();

        ApFloat value;
        bool    isExact  = false;
        bool    overflow = false;
        value.set(intVal, targetBits, isExact, overflow);
        if (overflow)
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castFloatToIntLike(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
        const ApFloat&     srcVal     = src.getFloat();
        const uint32_t     targetBits = targetType.intLikeBits();
        const bool         isUnsigned = targetType.isIntLikeUnsigned();

        bool         isExact  = false;
        bool         overflow = false;
        const ApsInt value    = srcVal.toInt(targetBits, isUnsigned, isExact, overflow);
        if (overflow)
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castFloatToFloat(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
        const ApFloat&     floatVal   = src.getFloat();
        const uint32_t     targetBits = targetType.floatBits();

        bool          isExact  = false;
        bool          overflow = false;
        const ApFloat value    = floatVal.convertTo(targetBits, isExact, overflow);
        if (overflow)
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        return ctx.cstMgr().addConstant(ctx, result);
    }

}

bool Sema::castAllowed(const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef) const
{
    auto&              ctx        = *ctx_;
    const TypeManager& typeMgr    = ctx.typeMgr();
    const TypeInfo&    srcType    = typeMgr.get(srcTypeRef);
    const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
    
    if (castCtx.kind == CastKind::Explicit && castCtx.flags.has(CastFlagsE::BitCast))
    {
        const bool srcScalar = srcType.isIntLike() || srcType.isFloat();
        const bool dstScalar = targetType.isIntLike() || targetType.isFloat();

        if (!srcScalar || !dstScalar)
        {
            raiseCannotCast(castCtx.errorNodeRef, srcTypeRef, targetTypeRef);
            return false;
        }

        const uint32_t srcBits = srcType.isIntLike() ? srcType.intLikeBits() : srcType.floatBits();
        const uint32_t dstBits = targetType.isIntLike() ? targetType.intLikeBits() : targetType.floatBits();
        if (srcBits == dstBits && srcBits != 0)
            return true;

        raiseCannotCast(castCtx.errorNodeRef, srcTypeRef, targetTypeRef);
        return false;
    }

    if (srcTypeRef == targetTypeRef)
        return true;
    
    switch (castCtx.kind)
    {
        case CastKind::LiteralSuffix:
            if (srcType.isChar() && targetType.isIntUnsigned())
                return true;
            if (srcType.isChar() && targetType.isRune())
                return true;
            if (srcType.isInt() && targetType.isInt())
                return true;
            if (srcType.isInt() && targetType.isFloat())
                return true;
            if (srcType.isFloat() && targetType.isFloat())
                return true;
            break;

        case CastKind::Promotion:
        case CastKind::Explicit:
            if (srcType.canBePromoted() && targetType.canBePromoted())
                return true;
            break;

        default:
            SWC_UNREACHABLE();
    }

    raiseCannotCast(castCtx.errorNodeRef, srcTypeRef, targetTypeRef);
    return false;
}

ConstantRef Sema::castConstant(const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef)
{
    const ConstantValue& src = cstMgr().get(srcRef);
    if (src.typeRef() == targetTypeRef)
        return srcRef;

    if (!castAllowed(castCtx, src.typeRef(), targetTypeRef))
        return ConstantRef::invalid();

    if (castCtx.kind == CastKind::Explicit && castCtx.flags.has(CastFlagsE::BitCast))
        return bitCastConstant(*this, castCtx, srcRef, targetTypeRef);

    auto&              ctx        = *ctx_;
    const TypeManager& typeMgr    = ctx.typeMgr();
    const TypeInfo&    srcType    = typeMgr.get(src.typeRef());
    const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

    if (srcType.isIntLike() && targetType.isIntLike())
        return castIntLikeToIntLike(*this, castCtx, src, targetTypeRef);

    if (srcType.isIntLike() && targetType.isFloat())
        return castIntLikeToFloat(*this, castCtx, src, targetTypeRef);

    if (srcType.isFloat() && targetType.isFloat())
        return castFloatToFloat(*this, castCtx, src, targetTypeRef);

    if (srcType.isFloat() && targetType.isIntLike())
        return castFloatToIntLike(*this, castCtx, src, targetTypeRef);

    raiseInternalError(node(castCtx.errorNodeRef));
    return ConstantRef::invalid();
}

bool Sema::promoteConstants(const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts)
{
    if (!force32BitInts && ops.nodeView[0].typeRef == ops.nodeView[1].typeRef)
        return true;

    if (ops.nodeView[0].type->canBePromoted() && ops.nodeView[1].type->canBePromoted())
    {
        const TypeRef promotedTypeRef = typeMgr().promote(ops.nodeView[0].typeRef, ops.nodeView[1].typeRef, force32BitInts);

        CastContext castCtx;
        castCtx.kind         = CastKind::Promotion;
        castCtx.errorNodeRef = ops.nodeView[0].nodeRef;

        leftRef = castConstant(castCtx, constantRefOf(ops.nodeView[0].nodeRef), promotedTypeRef);
        if (leftRef.isInvalid())
            return false;
        rightRef = castConstant(castCtx, constantRefOf(ops.nodeView[1].nodeRef), promotedTypeRef);
        if (rightRef.isInvalid())
            return false;
        return true;
    }

    SWC_UNREACHABLE();
}

AstVisitStepResult AstExplicitCastExpr::semaPostNode(Sema& sema) const
{
    if (sema.checkModifiers(*this, modifierFlags, AstModifierFlagsE::Bit | AstModifierFlagsE::UnConst) == Result::Error)
        return AstVisitStepResult::Stop;

    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    CastContext castCtx;
    castCtx.kind = CastKind::Explicit;
    if (modifierFlags.has(AstModifierFlagsE::Bit))
        castCtx.flags.add(CastFlagsE::BitCast);
    castCtx.errorNodeRef = nodeTypeView.nodeRef;
    if (!sema.castAllowed(castCtx, nodeExprView.typeRef, nodeTypeView.typeRef))
        return AstVisitStepResult::Stop;

    if (sema.hasConstant(nodeExprRef))
    {
        const ConstantRef cstRef = sema.castConstant(castCtx, nodeExprView.cstRef, nodeTypeView.typeRef);
        if (cstRef.isInvalid())
            return AstVisitStepResult::Stop;
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    sema.setType(sema.curNodeRef(), nodeTypeView.typeRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
