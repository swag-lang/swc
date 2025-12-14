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
    bool isFolding(const CastContext& c)
    {
        return c.fold != nullptr && c.fold->srcConstRef.isValid();
    }

    ConstantRef foldSrc(const CastContext& c)
    {
        return c.fold ? c.fold->srcConstRef : ConstantRef::invalid();
    }

    void setFoldOut(const CastContext& c, ConstantRef v)
    {
        if (c.fold && c.fold->outConstRef)
            *c.fold->outConstRef = v;
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

    // ---- fold ops (type-check always, fold only if castCtx.fold != nullptr) ----

    bool foldOpIdentity(Sema&, CastContext& castCtx, TypeRef, TypeRef)
    {
        if (isFolding(castCtx))
            setFoldOut(castCtx, foldSrc(castCtx));
        return true;
    }

    bool foldOpBitCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();

        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        const bool srcScalar = srcType.isScalarNumeric();
        const bool dstScalar = dstType.isScalarNumeric();
        if (!srcScalar || !dstScalar)
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_bit_cast_invalid_type, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            return false;
        }

        const uint32_t sb = srcType.scalarNumericBits();
        const uint32_t db = dstType.scalarNumericBits();
        if (!(sb == db || !sb))
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_bit_cast_size, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src = sema.cstMgr().get(foldSrc(castCtx));

        const bool srcInt   = srcType.isIntLike();
        const bool srcFloat = srcType.isFloat();
        const bool dstInt   = dstType.isIntLike();
        const bool dstFloat = dstType.isFloat();

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
            setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
            return true;
        }

        if (srcFloat && dstFloat)
        {
            const ApFloat&      value  = src.getFloat();
            const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
            setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
            return true;
        }

        if (srcFloat && dstInt)
        {
            ApsInt              i      = bitCastToApInt(src.getFloat(), dstType.isIntLikeUnsigned());
            const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, dstType);
            setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
            return true;
        }

        if (srcInt && dstFloat)
        {
            ApFloat             f      = bitCastToApFloat(src.getIntLike(), dstBits);
            const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
            setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
            return true;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return false;
    }

    bool foldOpBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&           ctx     = sema.ctx();
        const TypeInfo& dstType = ctx.typeMgr().get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src            = sema.cstMgr().get(foldSrc(castCtx));
        const bool           b              = src.getBool();
        const auto           targetBits     = dstType.intLikeBits();
        const bool           targetUnsigned = dstType.isIntLikeUnsigned();

        const ApsInt        value(b ? 1 : 0, targetBits, targetUnsigned);
        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool foldOpIntLikeToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&           ctx     = sema.ctx();
        const TypeInfo& dstType = ctx.typeMgr().get(dstTypeRef);

        if (!dstType.isBool())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src   = sema.cstMgr().get(foldSrc(castCtx));
        const ApsInt         value = src.getIntLike();
        const bool           b     = !value.isZero();

        const ConstantValue result = ConstantValue::makeBool(ctx, b);
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool foldOpIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src   = sema.cstMgr().get(foldSrc(castCtx));
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
                castCtx.failValueNote(DiagnosticId::sema_err_signed_unsigned, srcTypeRef, dstTypeRef, value.toString(), DiagnosticId::sema_note_signed_unsigned);
                return false;
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
                        castCtx.failValueNote(DiagnosticId::sema_err_signed_unsigned, srcTypeRef, dstTypeRef, value.toString(), DiagnosticId::sema_note_unsigned_signed);
                        return false;
                    }
                }
            }
        }

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            castCtx.failure.valueStr   = value.toString();
            return false;
        }

        // Fold:
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
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool foldOpIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isFloat())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src        = sema.cstMgr().get(foldSrc(castCtx));
        const ApsInt         intVal     = src.getIntLike();
        const uint32_t       targetBits = dstType.floatBits();

        ApFloat value;
        bool    isExact  = false;
        bool    overflow = false;
        value.set(intVal, targetBits, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            castCtx.failure.valueStr   = intVal.toString();
            return false;
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool foldOpFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src    = sema.cstMgr().get(foldSrc(castCtx));
        const ApFloat&       srcVal = src.getFloat();

        const uint32_t targetBits = dstType.intLikeBits();
        const bool     isUnsigned = dstType.isIntLikeUnsigned();

        bool         isExact  = false;
        bool         overflow = false;
        const ApsInt value    = srcVal.toInt(targetBits, isUnsigned, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            castCtx.failure.valueStr   = srcVal.toString();
            return false;
        }

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool foldOpFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (!dstType.isFloat())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!isFolding(castCtx))
            return true;

        const ConstantValue& src        = sema.cstMgr().get(foldSrc(castCtx));
        const ApFloat&       floatVal   = src.getFloat();
        const uint32_t       targetBits = dstType.floatBits();

        bool          isExact  = false;
        bool          overflow = false;
        const ApFloat value    = floatVal.toFloat(targetBits, isExact, overflow);

        if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
        {
            castCtx.failure            = CastFailure{.diagId = DiagnosticId::sema_err_literal_overflow, .nodeRef = castCtx.errorNodeRef};
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.dstTypeRef = dstTypeRef;
            castCtx.failure.valueStr   = floatVal.toString();
            return false;
        }

        const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
        setFoldOut(castCtx, sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    bool analyseCastCore(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        castCtx.resetFailure();

        if (castCtx.fold && castCtx.fold->outConstRef)
            *castCtx.fold->outConstRef = ConstantRef::invalid();

        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& src     = typeMgr.get(srcTypeRef);
        const TypeInfo& dst     = typeMgr.get(dstTypeRef);

        if (srcTypeRef == dstTypeRef)
            return foldOpIdentity(sema, castCtx, srcTypeRef, dstTypeRef);

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
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        // BitCast flag has priority
        if (castCtx.flags.has(CastFlagsE::BitCast))
            return foldOpBitCast(sema, castCtx, srcTypeRef, dstTypeRef);

        if (src.isBool() && dst.isIntLike())
            return foldOpBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
        if (src.isIntLike() && dst.isBool())
            return foldOpIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef);

        if (src.isIntLike() && dst.isIntLike())
            return foldOpIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
        if (src.isIntLike() && dst.isFloat())
            return foldOpIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
        if (src.isFloat() && dst.isFloat())
            return foldOpFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
        if (src.isFloat() && dst.isIntLike())
            return foldOpFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return false;
    }
} // namespace

bool SemaCast::analyseCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    CastFoldContext* saved = castCtx.fold;
    castCtx.fold           = nullptr;
    const bool ok          = analyseCastCore(sema, castCtx, srcTypeRef, dstTypeRef);
    castCtx.fold           = saved;
    return ok;
}

bool SemaCast::foldConstantCast(Sema& sema, CastContext& castCtx, ConstantRef srcConstRef, TypeRef dstTypeRef, ConstantRef& outConstRef)
{
    outConstRef = ConstantRef::invalid();

    const ConstantValue& cst        = sema.cstMgr().get(srcConstRef);
    const TypeRef        srcTypeRef = cst.typeRef();

    CastFoldContext foldCtx{.srcConstRef = srcConstRef, .outConstRef = &outConstRef};

    CastFoldContext* saved = castCtx.fold;
    castCtx.fold           = &foldCtx;

    const bool ok = analyseCastCore(sema, castCtx, srcTypeRef, dstTypeRef);

    castCtx.fold = saved;
    return ok;
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

bool SemaCast::castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    if (!analyseCast(sema, castCtx, srcTypeRef, targetTypeRef))
    {
        emitCastFailure(sema, castCtx.failure);
        return false;
    }

    return true;
}

ConstantRef SemaCast::castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef)
{
    ConstantRef out = ConstantRef::invalid();
    if (!foldConstantCast(sema, castCtx, cstRef, targetTypeRef, out))
    {
        emitCastFailure(sema, castCtx.failure);
        return ConstantRef::invalid();
    }

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
