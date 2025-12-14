#include "pch.h"

#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaCast.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"
#include "SemaError.h"
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
        SWC_ASSERT(srcBits == dstBits || !srcBits);

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

        SemaError::raiseCannotCast(sema, castCtx.errorNodeRef, src.typeRef(), targetTypeRef);
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
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_signed_unsigned, castCtx.errorNodeRef);
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
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_signed_unsigned, castCtx.errorNodeRef);
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
            SemaError::raiseLiteralOverflow(sema, castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        // Adjust signedness to target without changing the numeric value.
        if (value.isUnsigned() != targetUnsigned)
        {
            if (value.isUnsigned() && !targetUnsigned)
            {
                // unsigned -> signed: widen first so the sign bit is not taken from the old narrow width
                if (targetBits)
                    value.resize(targetBits + 1); // or checkBits; +1 ensures the top bit is 0 for values <= maxSigned
                value.setUnsigned(false);
                if (targetBits)
                    value.resize(targetBits);
            }
            else
            {
                // signed -> unsigned (negative already rejected above)
                // widen first too, to avoid reinterpreting a narrow signed value's the sign bit as data
                if (targetBits)
                    value.resize(targetBits);
                value.setUnsigned(true);
            }
        }
        else
        {
            if (targetBits)
                value.resize(targetBits);
        }

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
            SemaError::raiseLiteralOverflow(sema, castCtx.errorNodeRef, src, targetTypeRef);
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
            SemaError::raiseLiteralOverflow(sema, castCtx.errorNodeRef, src, targetTypeRef);
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
            SemaError::raiseLiteralOverflow(sema, castCtx.errorNodeRef, src, targetTypeRef);
            return ConstantRef::invalid();
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        return sema.cstMgr().addConstant(ctx, result);
    }

    ConstantRef evalCastPlanOnConstant(Sema& sema, const CastPlan& plan, ConstantRef srcRef)
    {
        const ConstantValue& cst = sema.cstMgr().get(srcRef);

        switch (plan.op)
        {
            case CastOp::Identity: return srcRef;
            case CastOp::BitCast: return bitCastConstant(sema, plan.ctx, srcRef, plan.dstType);
            case CastOp::BoolToIntLike: return castBoolToIntLike(sema, plan.ctx, cst, plan.dstType);
            case CastOp::IntLikeToBool: return castIntLikeToBool(sema, plan.ctx, cst, plan.dstType);
            case CastOp::IntLikeToIntLike: return castIntLikeToIntLike(sema, plan.ctx, cst, plan.dstType);
            case CastOp::IntLikeToFloat: return castIntLikeToFloat(sema, plan.ctx, cst, plan.dstType);
            case CastOp::FloatToFloat: return castFloatToFloat(sema, plan.ctx, cst, plan.dstType);
            case CastOp::FloatToIntLike: return castFloatToIntLike(sema, plan.ctx, cst, plan.dstType);
            default: SWC_UNREACHABLE();
        }
    }

    CastPlanOrFailure analyzeCast(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& src     = typeMgr.get(srcTypeRef);
        const TypeInfo& dst     = typeMgr.get(dstTypeRef);

        if (srcTypeRef == dstTypeRef)
            return CastPlan{CastOp::Identity, srcTypeRef, dstTypeRef, castCtx};

        if (castCtx.flags.has(CastFlagsE::BitCast))
        {
            // Validate bitcast constraints here once
            const bool srcScalar = src.isScalarNumeric();
            const bool dstScalar = dst.isScalarNumeric();
            if (!srcScalar || !dstScalar)
            {
                CastFailure f{DiagnosticId::sema_err_bit_cast_invalid_type, castCtx.errorNodeRef};
                f.typeArg = !srcScalar ? srcTypeRef : dstTypeRef;
                return f;
            }
            const uint32_t sb = src.scalarNumericBits();
            const uint32_t db = dst.scalarNumericBits();
            if (!(sb == db || !sb))
            {
                CastFailure f{DiagnosticId::sema_err_bit_cast_size, castCtx.errorNodeRef};
                f.leftType  = srcTypeRef;
                f.rightType = dstTypeRef;
                return f;
            }
            return CastPlan{CastOp::BitCast, srcTypeRef, dstTypeRef, castCtx};
        }

        // Kind rules (your existing switch, unchanged in spirit)
        auto kindAllows = [&] {
            switch (castCtx.kind)
            {
                case CastKind::LiteralSuffix:
                    if (src.isChar() && dst.isIntUnsigned())
                        return true;
                    if (src.isChar() && dst.isRune())
                        return true;
                    if (src.isInt() && dst.isInt())
                        return true;
                    if (src.isInt() && dst.isFloat())
                        return true;
                    if (src.isFloat() && dst.isFloat())
                        return true;
                    return false;
                case CastKind::Promotion:
                    return src.isScalarNumeric() && dst.isScalarNumeric();
                case CastKind::Explicit:
                    if (src.isScalarNumeric() && dst.isScalarNumeric())
                        return true;
                    if ((src.isBool() && dst.isIntLike()) || (src.isIntLike() && dst.isBool()))
                        return true;
                    return false;
                case CastKind::Implicit:
                    return src.isScalarNumeric() && dst.isScalarNumeric();
                default:
                    SWC_UNREACHABLE();
            }
        };

        if (!kindAllows())
        {
            CastFailure f{DiagnosticId::sema_err_cannot_cast, castCtx.errorNodeRef};
            f.leftType  = srcTypeRef;
            f.rightType = dstTypeRef;
            return f;
        }

        // Decide operation
        if (src.isBool() && dst.isIntLike())
            return CastPlan{CastOp::BoolToIntLike, srcTypeRef, dstTypeRef, castCtx};
        if (src.isIntLike() && dst.isBool())
            return CastPlan{CastOp::IntLikeToBool, srcTypeRef, dstTypeRef, castCtx};

        if (src.isIntLike() && dst.isIntLike())
            return CastPlan{CastOp::IntLikeToIntLike, srcTypeRef, dstTypeRef, castCtx};
        if (src.isIntLike() && dst.isFloat())
            return CastPlan{CastOp::IntLikeToFloat, srcTypeRef, dstTypeRef, castCtx};
        if (src.isFloat() && dst.isFloat())
            return CastPlan{CastOp::FloatToFloat, srcTypeRef, dstTypeRef, castCtx};
        if (src.isFloat() && dst.isIntLike())
            return CastPlan{CastOp::FloatToIntLike, srcTypeRef, dstTypeRef, castCtx};

        // If kindAllows was right, should not happen
        CastFailure f{DiagnosticId::sema_err_cannot_cast, castCtx.errorNodeRef};
        f.leftType  = srcTypeRef;
        f.rightType = dstTypeRef;
        return f;
    }

    void emitCastFailure(Sema& sema, const CastFailure& f)
    {
        auto diag = SemaError::report(sema, f.diagId, f.nodeRef);

        switch (f.diagId)
        {
            case DiagnosticId::sema_err_bit_cast_invalid_type:
                diag.addArgument(Diagnostic::ARG_TYPE, f.typeArg);
                break;
            case DiagnosticId::sema_err_bit_cast_size:
                diag.addArgument(Diagnostic::ARG_LEFT, f.leftType);
                diag.addArgument(Diagnostic::ARG_RIGHT, f.rightType);
                break;
            default:
                diag.addArgument(Diagnostic::ARG_LEFT, f.leftType);
                diag.addArgument(Diagnostic::ARG_RIGHT, f.rightType);
                break;
        }

        diag.report(sema.ctx());
    }
}

std::optional<CastFailure> SemaCast::check(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef)
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
            CastFailure f;
            f.diagId  = DiagnosticId::sema_err_bit_cast_invalid_type;
            f.nodeRef = castCtx.errorNodeRef;
            f.typeArg = !srcScalar ? srcTypeRef : targetTypeRef;
            return f;
        }

        const uint32_t srcBits = srcType.scalarNumericBits();
        const uint32_t dstBits = targetType.scalarNumericBits();
        if (srcBits == dstBits || !srcBits)
            return std::nullopt;

        CastFailure f;
        f.diagId    = DiagnosticId::sema_err_bit_cast_size;
        f.nodeRef   = castCtx.errorNodeRef;
        f.leftType  = srcTypeRef;
        f.rightType = targetTypeRef;
        return f;
    }

    if (srcTypeRef == targetTypeRef)
        return std::nullopt;

    switch (castCtx.kind)
    {
        case CastKind::LiteralSuffix:
            if (srcType.isChar() && targetType.isIntUnsigned())
                return std::nullopt;
            if (srcType.isChar() && targetType.isRune())
                return std::nullopt;
            if (srcType.isInt() && targetType.isInt())
                return std::nullopt;
            if (srcType.isInt() && targetType.isFloat())
                return std::nullopt;
            if (srcType.isFloat() && targetType.isFloat())
                return std::nullopt;
            break;

        case CastKind::Promotion:
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return std::nullopt;
            break;

        case CastKind::Explicit:
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return std::nullopt;
            if ((srcType.isBool() && targetType.isIntLike()) ||
                (srcType.isIntLike() && targetType.isBool()))
                return std::nullopt;
            break;

        case CastKind::Implicit:
            if (srcType.isScalarNumeric() && targetType.isScalarNumeric())
                return std::nullopt;
            break;

        default:
            SWC_UNREACHABLE();
    }

    // generic failure (no emission here)
    CastFailure f;
    f.diagId    = DiagnosticId::sema_err_cannot_cast; // or whatever your generic id is
    f.nodeRef   = castCtx.errorNodeRef;
    f.leftType  = srcTypeRef;
    f.rightType = targetTypeRef;
    return f;
}

bool SemaCast::castAllowed(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    const auto planOrFail = analyzeCast(sema, castCtx, srcTypeRef, targetTypeRef);
    if (const auto* f = std::get_if<CastFailure>(&planOrFail))
    {
        emitCastFailure(sema, *f);
        return false;
    }

    return true;
}

ConstantRef SemaCast::castConstant(Sema& sema, const CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef)
{
    const ConstantValue& cst = sema.cstMgr().get(cstRef);

    const auto planOrFail = analyzeCast(sema, castCtx, cst.typeRef(), targetTypeRef);
    if (const auto* f = std::get_if<CastFailure>(&planOrFail))
    {
        emitCastFailure(sema, *f);
        return ConstantRef::invalid();
    }

    return evalCastPlanOnConstant(sema, std::get<CastPlan>(planOrFail), cstRef);
}

bool SemaCast::promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts)
{
    if (!force32BitInts && ops.nodeView[0].typeRef == ops.nodeView[1].typeRef)
        return true;

    if (ops.nodeView[0].type->isScalarNumeric() && ops.nodeView[1].type->isScalarNumeric())
    {
        auto isConcreteScalar = [](const TypeInfo& t) -> bool {
            if (!t.isScalarNumeric())
                return false;

            if (t.isIntLike())
                return t.intLikeBits() != 0;

            if (t.isFloat())
                return t.floatBits() != 0;

            return false;
        };

        const bool leftConcrete  = isConcreteScalar(*ops.nodeView[0].type);
        const bool rightConcrete = isConcreteScalar(*ops.nodeView[1].type);

        // Start from the original constant refs
        ConstantRef leftSrc  = ops.nodeView[0].cstRef;
        ConstantRef rightSrc = ops.nodeView[1].cstRef;

        // Concretize only in the mixed case: one concrete, the other not.
        if (leftConcrete != rightConcrete)
        {
            bool overflow;
            if (!leftConcrete)
            {
                leftSrc = concretizeConstant(sema, leftSrc, overflow);
                if (overflow)
                {
                    SemaError::raiseLiteralTooBig(sema, ops.nodeView[0].nodeRef, sema.cstMgr().get(leftSrc));
                    return false;
                }
            }

            if (!rightConcrete)
            {
                rightSrc = concretizeConstant(sema, rightSrc, overflow);
                if (overflow)
                {
                    SemaError::raiseLiteralTooBig(sema, ops.nodeView[1].nodeRef, sema.cstMgr().get(rightSrc));
                    return false;
                }
            }
        }

        const TypeRef promotedTypeRef = sema.typeMgr().promote(ops.nodeView[0].typeRef, ops.nodeView[1].typeRef, force32BitInts);

        CastContext castCtx(CastKind::Promotion);
        castCtx.errorNodeRef = ops.nodeView[0].nodeRef;

        leftRef = castConstant(sema, castCtx, leftSrc, promotedTypeRef);
        if (leftRef.isInvalid())
            return false;

        rightRef = castConstant(sema, castCtx, rightSrc, promotedTypeRef);
        if (rightRef.isInvalid())
            return false;

        return true;
    }

    SWC_UNREACHABLE();
}

ConstantRef SemaCast::concretizeConstant(Sema& sema, ConstantRef cstRef, bool& overflow)
{
    auto&                ctx     = sema.ctx();
    const TypeManager&   typeMgr = ctx.typeMgr();
    const ConstantValue& src     = sema.cstMgr().get(cstRef);
    const TypeInfo&      ty      = typeMgr.get(src.typeRef());

    overflow = false;

    if (!ty.isScalarNumeric())
        return cstRef;

    if (ty.isIntLike())
    {
        // Already sized.
        if (ty.intLikeBits() != 0)
            return cstRef;

        ApsInt value = src.getIntLike();

        // Preserve the constant's signedness.
        const bool unsignedTarget = value.isUnsigned();

        // Smallest standard width (8/16/32/64/...) for this value & signedness.
        uint32_t concreteBits = value.minBits();
        concreteBits          = std::max(concreteBits, 32u);

        if (concreteBits > 64u)
        {
            overflow = true;
            return cstRef;
        }

        if (value.isUnsigned() != unsignedTarget)
            value.setUnsigned(unsignedTarget);
        value.resize(concreteBits);

        const TypeRef       concreteTypeRef = typeMgr.getTypeInt(concreteBits, unsignedTarget);
        const TypeInfo&     concreteTy      = typeMgr.get(concreteTypeRef);
        const ConstantValue result          = ConstantValue::makeFromIntLike(ctx, value, concreteTy);
        return sema.cstMgr().addConstant(ctx, result);
    }

    if (ty.isFloat())
    {
        // Already sized.
        if (ty.floatBits() != 0)
            return cstRef;

        const ApFloat& srcF = src.getFloat();

        uint32_t concreteBits = srcF.minBits();
        concreteBits          = std::max(concreteBits, 32u);

        bool    isExact   = false;
        ApFloat concreteF = srcF.toFloat(concreteBits, isExact, overflow);

        // If for any reason conversion reports overflow, keep original.
        if (overflow)
            concreteF = srcF;

        const ConstantValue result = ConstantValue::makeFloat(ctx, concreteF, concreteBits);
        return sema.cstMgr().addConstant(ctx, result);
    }

    return cstRef;
}

SWC_END_NAMESPACE()
