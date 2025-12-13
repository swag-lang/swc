#include "pch.h"

#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaCast.h"
#include "Sema/Type/TypeManager.h"
#include "SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ApsInt bitCastToApInt(const ApFloat& src, bool isUnsigned)
    {
        const uint32_t bw = src.bitWidth();

        if (bw == 32)
        {
            const float f = src.asFloat();
            uint32_t    u = 0;
            std::memcpy(&u, &f, sizeof(u));
            return ApsInt(u, 32, isUnsigned);
        }

        if (bw == 64)
        {
            const double d = src.asDouble();
            int64_t      u = 0;
            std::memcpy(&u, &d, sizeof(u));
            return ApsInt(u, 64, isUnsigned);
        }

        SWC_UNREACHABLE();
    }

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits)
    {
        SWC_ASSERT(floatBits == 32 || floatBits == 64);
        SWC_ASSERT(src.bitWidth() == floatBits);

        const uint64_t raw = src.asI64();

        if (floatBits == 32)
        {
            const uint32_t u = static_cast<uint32_t>(raw);
            float          f = 0.0f;
            std::memcpy(&f, &u, sizeof(f));
            return ApFloat(f);
        }

        if (floatBits == 64)
        {
            const uint64_t u = raw;
            double         d = 0.0;
            std::memcpy(&d, &u, sizeof(d));
            return ApFloat(d);
        }

        SWC_UNREACHABLE();
    }

    ConstantRef castBoolToIntLike(Sema& sema, const CastContext&, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

        SWC_ASSERT(targetType.isIntLike());

        const bool b              = src.getBool();
        const auto targetBits     = targetType.intLikeBits();
        const bool targetUnsigned = targetType.isIntLikeUnsigned();

        // Represent bool as 0 / 1 in the target integer type.
        const ApsInt value(b ? 1 : 0, targetBits, targetUnsigned);

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
        return sema.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castIntLikeToBool(Sema& sema, const CastContext&, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

        SWC_ASSERT(targetType.isBool());

        const ApsInt value = src.getIntLike();

        // Standard "to bool" semantics: 0 -> false, non-zero -> true.
        const bool b = !value.isZero();

        const ConstantValue result = ConstantValue::makeBool(ctx, b);
        return sema.cstMgr().addConstant(ctx, result);
    }

    ConstantRef bitCastConstant(Sema& sema, const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef)
    {
        auto&                ctx        = sema.ctx();
        const TypeManager&   typeMgr    = ctx.typeMgr();
        const ConstantValue& src        = sema.cstMgr().get(srcRef);
        const TypeInfo&      srcType    = typeMgr.get(src.typeRef());
        const TypeInfo&      targetType = typeMgr.get(targetTypeRef);

        const bool srcInt   = srcType.isIntLike();
        const bool srcFloat = srcType.isFloat();
        const bool dstInt   = targetType.isIntLike();
        const bool dstFloat = targetType.isFloat();

        SWC_ASSERT(srcInt || srcFloat);
        SWC_ASSERT(dstInt || dstFloat);

        const uint32_t srcBits = srcType.scalarNumericBits();
        const uint32_t dstBits = targetType.scalarNumericBits();
        SWC_ASSERT(srcBits == dstBits);

        // int-like -> int-like (same width): just re-tag signedness, do not change the underlying bit pattern.
        if (srcInt && dstInt)
        {
            ApsInt value = src.getIntLike();

            // Preserve bit pattern but reinterpret signedness for the target type
            if (value.isUnsigned() != targetType.isIntLikeUnsigned())
                value.setUnsigned(targetType.isIntLikeUnsigned());

            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
            return sema.cstMgr().addConstant(ctx, result);
        }

        // float -> float, same width: value is already that format.
        if (srcFloat && dstFloat)
        {
            const ApFloat&      value  = src.getFloat();
            const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
            return sema.cstMgr().addConstant(ctx, result);
        }

        // float -> int-like, same width: reinterpret raw bits.
        if (srcFloat && dstInt)
        {
            // Reinterpret a float bit pattern as integer without conversion
            ApsInt              i      = bitCastToApInt(src.getFloat(), targetType.isIntLikeUnsigned());
            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, targetType);
            return sema.cstMgr().addConstant(ctx, result);
        }

        if (srcInt && dstFloat)
        {
            // Reinterpret an integer bit pattern as float without conversion
            ApFloat             f      = bitCastToApFloat(src.getIntLike(), dstBits);
            const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
            return sema.cstMgr().addConstant(ctx, result);
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
            if (!value.isUnsigned() && value.isNegative() && !castCtx.flags.has(CastFlagsE::NoOverflow) && targetBits != 0)
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_signed_unsigned, castCtx.errorNodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, value.toString());
                diag.addElement(DiagnosticId::sema_note_signed_unsigned);
                diag.report(ctx);
                return ConstantRef::invalid();
            }

            // Compare in unsigned space.
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
                vCheck.resize(checkBits);

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

                ApsInt vCheck = value;
                if (!vCheck.isUnsigned())
                    vCheck.setUnsigned(true);
                vCheck.resize(checkBits);

                // maxSigned: 2^(N-1) - 1 (already computed above)
                // maxBits: 2^N - 1 (max value representable in N bits, regardless of sign)
                ApsInt maxBits = ApsInt::maxValue(targetBits, true);
                maxBits.resize(checkBits);

                ApsInt maxSignedU = maxSigned;
                if (!maxSignedU.isUnsigned())
                    maxSignedU.setUnsigned(true);
                maxSignedU.resize(checkBits);

                if (vCheck.gt(maxBits))
                {
                    // Value does NOT fit in N bits at all -> generic overflow.
                    overflow = true;
                }
                else if (vCheck.gt(maxSignedU))
                {
                    // Value fits in N bits, but outside signed range -> signed/unsigned error.
                    if (!castCtx.flags.has(CastFlagsE::NoOverflow))
                    {
                        auto diag = sema.reportError(DiagnosticId::sema_err_signed_unsigned, castCtx.errorNodeRef);
                        diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
                        diag.addArgument(Diagnostic::ARG_VALUE, value.toString());
                        diag.addElement(DiagnosticId::sema_note_unsigned_signed);
                        diag.report(ctx);
                        return ConstantRef::invalid();
                    }
                }
            }
        }

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        // Adjust signedness to target
        if (value.isUnsigned() != targetUnsigned)
            value.setUnsigned(targetUnsigned);

        // Resize to the target bit width (now safe; we already checked range)
        if (targetBits)
            value.resize(targetBits);

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
        return sema.cstMgr().addConstant(ctx, result);
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
        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        return sema.cstMgr().addConstant(ctx, result);
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
        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, targetType);
        return sema.cstMgr().addConstant(ctx, result);
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
        const ApFloat value    = floatVal.toFloat(targetBits, isExact, overflow);
        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            sema.raiseLiteralOverflow(castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        return sema.cstMgr().addConstant(ctx, result);
    }

}

bool SemaCast::castAllowed(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto&              ctx        = sema.ctx();
    const TypeManager& typeMgr    = ctx.typeMgr();
    const TypeInfo&    srcType    = typeMgr.get(srcTypeRef);
    const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

    if (castCtx.flags.has(CastFlagsE::BitCast))
    {
        const bool srcScalar = srcType.isScalarNumeric();
        const bool dstScalar = targetType.isScalarNumeric();

        if (!srcScalar || !dstScalar)
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_bit_cast_invalid_type, castCtx.errorNodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, !srcScalar ? srcTypeRef : targetTypeRef);
            diag.report(ctx);
            return false;
        }

        const uint32_t srcBits = srcType.scalarNumericBits();
        const uint32_t dstBits = targetType.scalarNumericBits();
        if (srcBits == dstBits)
            return true;

        auto diag = sema.reportError(DiagnosticId::sema_err_bit_cast_size, castCtx.errorNodeRef);
        diag.addArgument(Diagnostic::ARG_LEFT, srcTypeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, targetTypeRef);
        diag.report(ctx);
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
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return true;
            break;

        case CastKind::Explicit:
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return true;
            if ((srcType.isBool() && targetType.isIntLike()) || (srcType.isIntLike() && targetType.isBool()))
                return true;
            break;

        case CastKind::Implicit:
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return true;
            break;

        default:
            SWC_UNREACHABLE();
    }

    sema.raiseCannotCast(castCtx.errorNodeRef, srcTypeRef, targetTypeRef);
    return false;
}

ConstantRef SemaCast::castConstant(Sema& sema, const CastContext& castCtx, ConstantRef srcRef, TypeRef targetTypeRef)
{
    const ConstantValue& src = sema.cstMgr().get(srcRef);
    if (src.typeRef() == targetTypeRef)
        return srcRef;

    if (!castAllowed(sema, castCtx, src.typeRef(), targetTypeRef))
        return ConstantRef::invalid();

    if (castCtx.flags.has(CastFlagsE::BitCast))
        return bitCastConstant(sema, castCtx, srcRef, targetTypeRef);

    auto&              ctx        = sema.ctx();
    const TypeManager& typeMgr    = ctx.typeMgr();
    const TypeInfo&    srcType    = typeMgr.get(src.typeRef());
    const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

    if (srcType.isBool() && targetType.isIntLike())
        return castBoolToIntLike(sema, castCtx, src, targetTypeRef);

    if (srcType.isIntLike() && targetType.isBool())
        return castIntLikeToBool(sema, castCtx, src, targetTypeRef);

    if (srcType.isIntLike() && targetType.isIntLike())
        return castIntLikeToIntLike(sema, castCtx, src, targetTypeRef);

    if (srcType.isIntLike() && targetType.isFloat())
        return castIntLikeToFloat(sema, castCtx, src, targetTypeRef);

    if (srcType.isFloat() && targetType.isFloat())
        return castFloatToFloat(sema, castCtx, src, targetTypeRef);

    if (srcType.isFloat() && targetType.isIntLike())
        return castFloatToIntLike(sema, castCtx, src, targetTypeRef);

    sema.raiseInternalError(sema.node(castCtx.errorNodeRef));
    return ConstantRef::invalid();
}

bool SemaCast::promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts)
{
    if (!force32BitInts && ops.nodeView[0].typeRef == ops.nodeView[1].typeRef)
        return true;

    if (ops.nodeView[0].type->isScalarNumeric() && ops.nodeView[1].type->isScalarNumeric())
    {
        const TypeRef promotedTypeRef = sema.typeMgr().promote(ops.nodeView[0].typeRef, ops.nodeView[1].typeRef, force32BitInts);

        CastContext castCtx(CastKind::Promotion);
        castCtx.errorNodeRef = ops.nodeView[0].nodeRef;

        leftRef = castConstant(sema, castCtx, sema.constantRefOf(ops.nodeView[0].nodeRef), promotedTypeRef);
        if (leftRef.isInvalid())
            return false;
        rightRef = castConstant(sema, castCtx, sema.constantRefOf(ops.nodeView[1].nodeRef), promotedTypeRef);
        if (rightRef.isInvalid())
            return false;
        return true;
    }

    SWC_UNREACHABLE();
}

namespace
{
    // Returns true if `value` fits in exactly `bits` under the chosen signedness.
    // Uses trunc -> extend roundtrip to avoid needing special "min bits" APIs.
    bool fitsInBits(const ApsInt& valueIn, uint32_t bits, bool unsignedTarget)
    {
        SWC_ASSERT(bits > 0);

        // Work in a widened width so comparisons are meaningful after re-extension.
        const uint32_t checkBits = (valueIn.bitWidth() > bits + 1) ? valueIn.bitWidth() : (bits + 1);

        ApsInt canon = valueIn;
        if (canon.isUnsigned() != unsignedTarget)
            canon.setUnsigned(unsignedTarget);
        canon.resize(checkBits);

        // Truncate to candidate width...
        ApsInt round = canon;
        round.resize(bits);

        // ...then extend back and compare with canonical widened value.
        round.resize(checkBits);

        // ApsInt likely has eq(); if yours uses ==, replace this.
        return round.eq(canon);
    }

    uint32_t pickConcreteIntBits(const ApsInt& value, bool unsignedTarget)
    {
        uint32_t bits = 32;

        // Grow until it fits.
        while (!fitsInBits(value, bits, unsignedTarget))
        {
            // Double to keep it fast; you can clamp if your compiler has a max int width.
            bits *= 2;
            SWC_ASSERT(bits != 0); // overflow guard
        }

        return bits;
    }

    uint32_t pickConcreteFloatBits(const ApFloat& value)
    {
        // Never below 32. Prefer 32 if it doesn't overflow; otherwise 64; otherwise keep original.
        bool isExact  = false;
        bool overflow = false;

        (void) value.toFloat(32, isExact, overflow);
        if (!overflow)
            return 32;

        overflow = false;
        (void) value.toFloat(64, isExact, overflow);
        if (!overflow)
            return 64;

        // If it overflows even at 64, keep the current precision/width (must be >= 32).
        return (value.bitWidth() < 32) ? 32 : value.bitWidth();
    }
}

// Concretize an unsized int/float constant into a sized one (>= 32 bits).
ConstantRef SemaCast::concretizeConstant(Sema& sema, ConstantRef srcRef)
{
    auto&                ctx     = sema.ctx();
    const TypeManager&   typeMgr = ctx.typeMgr();
    const ConstantValue& src     = sema.cstMgr().get(srcRef);
    const TypeInfo&      ty      = typeMgr.get(src.typeRef());

    // Only numeric scalars are supported here.
    if (!ty.isScalarNumeric())
        return srcRef;

    // Unsized int-like
    if (ty.isIntLike())
    {
        const uint32_t bits = ty.intLikeBits();

        // If already sized, nothing to do.
        if (bits != 0)
            return srcRef;

        ApsInt     value          = src.getIntLike();
        const bool unsignedTarget = ty.isIntLikeUnsigned();

        const uint32_t concreteBits = (bits >= 32) ? bits : pickConcreteIntBits(value, unsignedTarget);

        // Resize the stored value to the chosen width.
        if (value.isUnsigned() != unsignedTarget)
            value.setUnsigned(unsignedTarget);
        value.resize(concreteBits);

        // You need a way to get a sized int-like type of `concreteBits` + signedness.
        const TypeRef concreteTypeRef = typeMgr.getTypeInt(concreteBits, unsignedTarget);

        const TypeInfo&     concreteTy = typeMgr.get(concreteTypeRef);
        const ConstantValue result     = ConstantValue::makeFromIntLike(ctx, value, concreteTy);
        return sema.cstMgr().addConstant(ctx, result);
    }

    // Unsized float
    if (ty.isFloat())
    {
        const uint32_t bits = ty.floatBits();

        if (bits != 0)
            return srcRef;

        const ApFloat& srcF         = src.getFloat();
        const uint32_t concreteBits = pickConcreteFloatBits(srcF);

        bool    isExact   = false;
        bool    overflow  = false;
        ApFloat concreteF = srcF.toFloat(concreteBits, isExact, overflow);

        // If this overflows even at chosen bits (shouldn't, given pickConcreteFloatBits),
        // fall back to keeping the original value/width.
        if (overflow)
        {
            concreteF = srcF;
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, concreteF, concreteBits);
        return sema.cstMgr().addConstant(ctx, result);
    }

    return srcRef;
}

SWC_END_NAMESPACE()
