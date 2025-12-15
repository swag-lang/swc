#include "pch.h"
#include "Math/Helpers.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

void SemaCast::foldConstantIdentity(CastContext& castCtx)
{
    castCtx.setFoldOut(castCtx.foldSrc());
}

bool SemaCast::foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType)
{
    auto& ctx = sema.ctx();

    const ConstantValue& src = sema.cstMgr().get(castCtx.foldSrc());

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
        castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcFloat && dstFloat)
    {
        const ApFloat&      value  = src.getFloat();
        const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
        castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcFloat && dstInt)
    {
        ApsInt              i      = Math::bitCastToApInt(src.getFloat(), dstType.isIntLikeUnsigned());
        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, dstType);
        castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcInt && dstFloat)
    {
        ApFloat             f      = Math::bitCastToApFloat(src.getIntLike(), dstBits);
        const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
        castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    // Should be unreachable given earlier asserts, but keep consistent error behavior.
    castCtx.fail(DiagnosticId::sema_err_cannot_cast, src.typeRef(), dstTypeRef);
    return false;
}

bool SemaCast::foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType        = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src            = sema.cstMgr().get(castCtx.foldSrc());
    const bool           b              = src.getBool();
    const auto           targetBits     = dstType.intLikeBits();
    const bool           targetUnsigned = dstType.isIntLikeUnsigned();

    const ApsInt        value(b ? 1 : 0, targetBits, targetUnsigned);
    const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));

    return true;
}

bool SemaCast::foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx)
{
    const auto& ctx = sema.ctx();

    const ConstantValue& src   = sema.cstMgr().get(castCtx.foldSrc());
    const ApsInt         value = src.getIntLike();
    const bool           b     = !value.isZero();

    const ConstantValue result = ConstantValue::makeBool(ctx, b);
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));

    return true;
}

bool SemaCast::foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    auto& ctx = sema.ctx();

    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src     = sema.cstMgr().get(castCtx.foldSrc());
    ApsInt               value   = src.getIntLike();

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
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool SemaCast::foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType    = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src        = sema.cstMgr().get(castCtx.foldSrc());
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
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool SemaCast::foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src     = sema.cstMgr().get(castCtx.foldSrc());
    const ApFloat&       srcVal  = src.getFloat();

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
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool SemaCast::foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType    = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src        = sema.cstMgr().get(castCtx.foldSrc());
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
    castCtx.setFoldOut(sema.cstMgr().addConstant(ctx, result));
    return true;
}

ConstantRef SemaCast::castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef)
{
    const ConstantValue& cst        = sema.cstMgr().get(cstRef);
    const TypeRef        srcTypeRef = cst.typeRef();
    castCtx.srcConstRef             = cstRef;

    const bool ok = castAllowed(sema, castCtx, srcTypeRef, targetTypeRef);
    if (!ok)
    {
        emitCastFailure(sema, castCtx.failure);
        return ConstantRef::invalid();
    }

    return castCtx.outConstRef;
}

bool SemaCast::promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts)
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

        CastContext leftCastCtx(CastKind::Promotion);
        leftCastCtx.errorNodeRef = ops.nodeView[0].nodeRef;
        leftCstRef               = castConstant(sema, leftCastCtx, leftSrc, promotedTypeRef);
        if (leftCstRef.isInvalid())
            return false;

        CastContext rightCastCtx(CastKind::Promotion);
        rightCastCtx.errorNodeRef = ops.nodeView[0].nodeRef;
        rightCstRef               = castConstant(sema, rightCastCtx, rightSrc, promotedTypeRef);
        if (rightCstRef.isInvalid())
            return false;

        return true;
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE()
