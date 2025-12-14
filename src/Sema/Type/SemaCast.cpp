// ReSharper disable CppClangTidyClangDiagnosticMissingDesignatedFieldInitializers
#include "pch.h"
#include "Sema/Type/SemaCast.h"
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    CastFailure makeCannotCastFailure(const CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        CastFailure f{.diagId = DiagnosticId::sema_err_cannot_cast, .nodeRef = castCtx.errorNodeRef};
        f.srcTypeRef = srcTypeRef;
        f.dstTypeRef = dstTypeRef;
        return f;
    }

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

    std::optional<CastFailure> opIdentity(
        Sema&,
        const CastContext&,
        TypeRef,
        TypeRef,
        CastMode     mode,
        ConstantRef  srcConst,
        ConstantRef* outConst)
    {
        if (mode == CastMode::Evaluate && outConst)
            *outConst = srcConst;
        return std::nullopt;
    }

    std::optional<CastFailure> opBitCast(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();

        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        const bool srcScalar = srcType.isScalarNumeric();
        const bool dstScalar = dstType.isScalarNumeric();
        if (!srcScalar || !dstScalar)
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_bit_cast_invalid_type, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            return f;
        }

        const uint32_t sb = srcType.scalarNumericBits();
        const uint32_t db = dstType.scalarNumericBits();
        if (!(sb == db || !sb))
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_bit_cast_size, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            return f;
        }

        // Fold if constant provided
        if (mode == CastMode::Evaluate && srcConst.isValid() && outConst)
        {
            const ConstantValue& src = sema.cstMgr().get(srcConst);

            const bool srcInt   = srcType.isIntLike();
            const bool srcFloat = srcType.isFloat();
            const bool dstInt   = dstType.isIntLike();
            const bool dstFloat = dstType.isFloat();

            // If the op says BitCast, these should be scalar numeric but keep assertions.
            SWC_ASSERT(srcInt || srcFloat);
            SWC_ASSERT(dstInt || dstFloat);

            const uint32_t srcBits = srcType.scalarNumericBits();
            const uint32_t dstBits = dstType.scalarNumericBits();
            SWC_ASSERT(srcBits == dstBits || !srcBits);

            if (srcInt && dstInt)
            {
                ApsInt value = src.getIntLike();
                if (value.isUnsigned() != dstType.isIntLikeUnsigned())
                    value.setUnsigned(dstType.isIntLikeUnsigned());

                const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
                *outConst                  = sema.cstMgr().addConstant(ctx, result);
                return std::nullopt;
            }

            if (srcFloat && dstFloat)
            {
                const ApFloat&      value  = src.getFloat();
                const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
                *outConst                  = sema.cstMgr().addConstant(ctx, result);
                return std::nullopt;
            }

            if (srcFloat && dstInt)
            {
                ApsInt              i      = bitCastToApInt(src.getFloat(), dstType.isIntLikeUnsigned());
                const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, dstType);
                *outConst                  = sema.cstMgr().addConstant(ctx, result);
                return std::nullopt;
            }

            if (srcInt && dstFloat)
            {
                ApFloat             f      = bitCastToApFloat(src.getIntLike(), dstBits);
                const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
                *outConst                  = sema.cstMgr().addConstant(ctx, result);
                return std::nullopt;
            }

            // Op mismatch or unexpected type combo
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);
        }

        return std::nullopt;
    }

    std::optional<CastFailure> opBoolToIntLike(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&           ctx     = sema.ctx();
        const TypeInfo& dstType = ctx.typeMgr().get(dstTypeRef);

        // Type-level validation (works for non-constants too)
        if (!dstType.isIntLike())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        if (mode == CastMode::Evaluate && srcConst.isValid() && outConst)
        {
            const ConstantValue& src            = sema.cstMgr().get(srcConst);
            const bool           b              = src.getBool();
            const auto           targetBits     = dstType.intLikeBits();
            const bool           targetUnsigned = dstType.isIntLikeUnsigned();

            const ApsInt        value(b ? 1 : 0, targetBits, targetUnsigned);
            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }
        return std::nullopt;
    }

    std::optional<CastFailure> opIntLikeToBool(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&           ctx     = sema.ctx();
        const TypeInfo& dstType = ctx.typeMgr().get(dstTypeRef);

        if (!dstType.isBool())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        if (mode == CastMode::Evaluate && srcConst.isValid() && outConst)
        {
            const ConstantValue& src   = sema.cstMgr().get(srcConst);
            const ApsInt         value = src.getIntLike();
            const bool           b     = !value.isZero();

            const ConstantValue result = ConstantValue::makeBool(ctx, b);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }
        return std::nullopt;
    }

    std::optional<CastFailure> opIntLikeToIntLike(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isIntLike())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        // If we have no constant, we can’t do value-dependent overflow checks here.
        // That’s OK: this function still validates the cast structurally.
        if (!srcConst.isValid())
            return std::nullopt;

        const ConstantValue& src   = sema.cstMgr().get(srcConst);
        ApsInt               value = src.getIntLike();

        const uint32_t targetBits     = dstType.intLikeBits();
        const bool     targetUnsigned = dstType.isIntLikeUnsigned();
        const uint32_t valueBits      = value.bitWidth();

        const uint32_t checkBits = (valueBits > targetBits + 1) ? valueBits : (targetBits + 1);
        bool           overflow  = false;

        if (targetUnsigned)
        {
            if (!value.isUnsigned() && value.isNegative() && !castCtx.flags.has(CastFlagsE::NoOverflow) && targetBits != 0)
            {
                CastFailure f{.diagId = DiagnosticId::sema_err_signed_unsigned, .nodeRef = castCtx.errorNodeRef};
                f.srcTypeRef = srcTypeRef;
                f.dstTypeRef = dstTypeRef;
                f.valueStr   = value.toString();
                f.noteId     = DiagnosticId::sema_note_signed_unsigned;
                return f;
            }

            ApsInt vCheck = value;
            if (!vCheck.isUnsigned())
                vCheck.setUnsigned(true);

            vCheck.resize(checkBits);

            ApsInt maxCheck = ApsInt::maxValue(targetBits, true);
            maxCheck.resize(checkBits);

            if (vCheck.gt(maxCheck))
                overflow = true;
        }
        else
        {
            ApsInt minSigned = ApsInt::minValue(targetBits, false);
            ApsInt maxSigned = ApsInt::maxValue(targetBits, false);

            if (!value.isUnsigned())
            {
                ApsInt vCheck = value;
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
                ApsInt vCheck = value;
                vCheck.resize(checkBits);

                ApsInt maxBits = ApsInt::maxValue(targetBits, true);
                maxBits.resize(checkBits);

                ApsInt maxSignedU = maxSigned;
                if (!maxSignedU.isUnsigned())
                    maxSignedU.setUnsigned(true);
                maxSignedU.resize(checkBits);

                if (vCheck.gt(maxBits))
                {
                    overflow = true;
                }
                else if (vCheck.gt(maxSignedU))
                {
                    if (!castCtx.flags.has(CastFlagsE::NoOverflow))
                    {
                        CastFailure f{.diagId = DiagnosticId::sema_err_signed_unsigned, .nodeRef = castCtx.errorNodeRef};
                        f.srcTypeRef = srcTypeRef;
                        f.dstTypeRef = dstTypeRef;
                        f.valueStr   = value.toString();
                        f.noteId     = DiagnosticId::sema_note_unsigned_signed;
                        return f;
                    }
                }
            }
        }

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            f.valueStr   = value.toString();
            return f;
        }

        // Fold if requested
        if (mode == CastMode::Evaluate && outConst)
        {
            // Adjust signedness to the target without changing the numeric value.
            if (value.isUnsigned() != targetUnsigned)
            {
                if (value.isUnsigned() && !targetUnsigned)
                {
                    if (targetBits)
                        value.resize(targetBits + 1);
                    value.setUnsigned(false);
                    if (targetBits)
                        value.resize(targetBits);
                }
                else
                {
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

            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }

        return std::nullopt;
    }

    std::optional<CastFailure> opIntLikeToFloat(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isFloat())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        if (!srcConst.isValid())
            return std::nullopt;

        const ConstantValue& src        = sema.cstMgr().get(srcConst);
        const ApsInt         intVal     = src.getIntLike();
        const uint32_t       targetBits = dstType.floatBits();

        ApFloat value;
        bool    isExact  = false;
        bool    overflow = false;
        value.set(intVal, targetBits, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            f.valueStr   = intVal.toString();
            return f;
        }

        if (mode == CastMode::Evaluate && outConst)
        {
            const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }

        return std::nullopt;
    }

    std::optional<CastFailure> opFloatToIntLike(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isIntLike())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        if (!srcConst.isValid())
            return std::nullopt;

        const ConstantValue& src    = sema.cstMgr().get(srcConst);
        const ApFloat&       srcVal = src.getFloat();

        const uint32_t targetBits = dstType.intLikeBits();
        const bool     isUnsigned = dstType.isIntLikeUnsigned();

        bool         isExact  = false;
        bool         overflow = false;
        const ApsInt value    = srcVal.toInt(targetBits, isUnsigned, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            f.valueStr   = srcVal.toString();
            return f;
        }

        if (mode == CastMode::Evaluate && outConst)
        {
            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }

        return std::nullopt;
    }

    std::optional<CastFailure> opFloatToFloat(
        Sema&              sema,
        const CastContext& castCtx,
        TypeRef            srcTypeRef,
        TypeRef            dstTypeRef,
        CastMode           mode,
        ConstantRef        srcConst,
        ConstantRef*       outConst)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isFloat())
            return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

        if (!srcConst.isValid())
            return std::nullopt;

        const ConstantValue& src        = sema.cstMgr().get(srcConst);
        const ApFloat&       floatVal   = src.getFloat();
        const uint32_t       targetBits = dstType.floatBits();

        bool          isExact  = false;
        bool          overflow = false;
        const ApFloat value    = floatVal.toFloat(targetBits, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            CastFailure f{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            f.srcTypeRef = srcTypeRef;
            f.dstTypeRef = dstTypeRef;
            f.valueStr   = floatVal.toString();
            return f;
        }

        if (mode == CastMode::Evaluate && outConst)
        {
            const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
            *outConst                  = sema.cstMgr().addConstant(ctx, result);
        }

        return std::nullopt;
    }
}

// Replaces both the old analyzeCast() (plan-building) + applyCastPlan() (execution).
// It analyses types/kind/flags, selects an op, validates, and optionally folds constants.
std::optional<CastFailure> SemaCast::analyseCast(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, CastMode mode, ConstantRef srcConst, ConstantRef* outConst)
{
    if (outConst)
        *outConst = ConstantRef::invalid();

    const auto&     typeMgr = sema.ctx().typeMgr();
    const TypeInfo& src     = typeMgr.get(srcTypeRef);
    const TypeInfo& dst     = typeMgr.get(dstTypeRef);

    if (srcTypeRef == dstTypeRef)
        return opIdentity(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);

    // Kind rules: Global / coarse only
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
        return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);

    // BitCast flag has priority (same behavior as before)
    if (castCtx.flags.has(CastFlagsE::BitCast))
        return opBitCast(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);

    if (src.isBool() && dst.isIntLike())
        return opBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);
    if (src.isIntLike() && dst.isBool())
        return opIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);

    if (src.isIntLike() && dst.isIntLike())
        return opIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);
    if (src.isIntLike() && dst.isFloat())
        return opIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);
    if (src.isFloat() && dst.isFloat())
        return opFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);
    if (src.isFloat() && dst.isIntLike())
        return opFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef, mode, srcConst, outConst);

    return makeCannotCastFailure(castCtx, srcTypeRef, dstTypeRef);
}

void SemaCast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    auto diag = SemaError::report(sema, f.diagId, f.nodeRef);

    diag.addArgument(Diagnostic::ARG_TYPE, f.srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, f.dstTypeRef);

    if (!f.valueStr.empty())
        diag.addArgument(Diagnostic::ARG_VALUE, f.valueStr);

    if (f.noteId != DiagnosticId::None)
        diag.addNote(f.noteId);

    diag.report(sema.ctx());
}

bool SemaCast::castAllowed(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    // Non-constant check: srcConst invalid
    if (const auto fail = analyseCast(sema, castCtx, srcTypeRef, targetTypeRef, CastMode::Check, ConstantRef::invalid(), nullptr))
    {
        emitCastFailure(sema, *fail);
        return false;
    }

    return true;
}

ConstantRef SemaCast::castConstant(Sema& sema, const CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef)
{
    const ConstantValue& cst = sema.cstMgr().get(cstRef);

    ConstantRef out = ConstantRef::invalid();
    if (const auto fail = analyseCast(sema, castCtx, cst.typeRef(), targetTypeRef, CastMode::Evaluate, cstRef, &out))
    {
        emitCastFailure(sema, *fail);
        return ConstantRef::invalid();
    }

    // If Evaluate was requested and folding was possible, out is valid.
    // Otherwise (future non-constant path), out could be invalid; for constants it should fold.
    return out.isValid() ? out : ConstantRef::invalid();
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

        ConstantRef leftSrc  = ops.nodeView[0].cstRef;
        ConstantRef rightSrc = ops.nodeView[1].cstRef;

        if (leftConcrete != rightConcrete)
        {
            bool overflow;
            if (!leftConcrete)
            {
                leftSrc = sema.cstMgr().concretizeConstant(sema.ctx(), leftSrc, overflow);
                if (overflow)
                {
                    SemaError::raiseLiteralTooBig(sema, ops.nodeView[0].nodeRef, sema.cstMgr().get(leftSrc));
                    return false;
                }
            }

            if (!rightConcrete)
            {
                rightSrc = sema.cstMgr().concretizeConstant(sema.ctx(), rightSrc, overflow);
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

SWC_END_NAMESPACE()
