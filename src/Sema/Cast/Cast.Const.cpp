#include "pch.h"
#include "Sema/Cast/Cast.h"
#include "Math/Helpers.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

bool Cast::concretizeConstant(Sema& sema, ConstantRef& result, CastContext& castCtx, ConstantRef cstRef, TypeInfo::Sign hintSign)
{
    if (!sema.cstMgr().concretizeConstant(sema, result, cstRef, hintSign))
    {
        castCtx.fail(DiagnosticId::sema_err_literal_too_big, sema.cstMgr().get(cstRef).typeRef(), TypeRef::invalid());
        return false;
    }

    return true;
}

void Cast::foldConstantIdentity(CastContext& castCtx)
{
    castCtx.setConstantFoldingResult(castCtx.constantFoldingSrc());
}

bool Cast::foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType)
{
    auto& ctx = sema.ctx();

    // Be sure constant is sized
    if (dstType.isInt())
    {
        ConstantRef newCstRef;
        if (!concretizeConstant(sema, newCstRef, castCtx, castCtx.constantFoldingSrc(), dstType.payloadIntSign()))
            return false;
        castCtx.setConstantFoldingSrc(newCstRef);
    }
    else if (dstType.isFloat())
    {
        ConstantRef newCstRef;
        if (!concretizeConstant(sema, newCstRef, castCtx, castCtx.constantFoldingSrc(), TypeInfo::Sign::Signed))
            return false;
        castCtx.setConstantFoldingSrc(newCstRef);
    }

    const ConstantValue& src = sema.cstMgr().get(castCtx.constantFoldingSrc());

    const bool srcInt   = srcType.isIntLike();
    const bool srcFloat = srcType.isFloat();
    const bool dstInt   = dstType.isIntLike();
    const bool dstFloat = dstType.isFloat();

    SWC_ASSERT(srcInt || srcFloat);
    SWC_ASSERT(dstInt || dstFloat);

    const uint32_t srcBits = srcType.payloadScalarNumericBits();
    const uint32_t dstBits = dstType.payloadScalarNumericBits();
    SWC_ASSERT(srcBits == dstBits || !srcBits);

    if (srcInt && dstInt)
    {
        ApsInt value = src.getIntLike();
        if (value.isUnsigned() != dstType.isIntLikeUnsigned())
            value.setUnsigned(dstType.isIntLikeUnsigned());

        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
        castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcFloat && dstFloat)
    {
        const ApFloat&      value  = src.getFloat();
        const ConstantValue result = ConstantValue::makeFloat(ctx, value, dstBits);
        castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcFloat && dstInt)
    {
        ApsInt              i      = Math::bitCastToApInt(src.getFloat(), dstType.isIntLikeUnsigned());
        const ConstantValue result = ConstantValue::makeFromIntLike(ctx, i, dstType);
        castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    if (srcInt && dstFloat)
    {
        ApFloat             f      = Math::bitCastToApFloat(src.getIntLike(), dstBits);
        const ConstantValue result = ConstantValue::makeFloat(ctx, f, dstBits);
        castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
        return true;
    }

    // Should be unreachable given earlier asserts, but keep consistent error behavior.
    castCtx.fail(DiagnosticId::sema_err_cannot_cast, src.typeRef(), dstTypeRef);
    return false;
}

bool Cast::foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType        = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src            = sema.cstMgr().get(castCtx.constantFoldingSrc());
    const bool           b              = src.getBool();
    const auto           targetBits     = dstType.payloadIntLikeBits();
    const bool           targetUnsigned = dstType.isIntLikeUnsigned();

    const ApsInt        value(b ? 1 : 0, targetBits, targetUnsigned);
    const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));

    return true;
}

bool Cast::foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx)
{
    const auto& ctx = sema.ctx();

    const ConstantValue& src   = sema.cstMgr().get(castCtx.constantFoldingSrc());
    const ApsInt         value = src.getIntLike();
    const bool           b     = !value.isZero();

    const ConstantValue result = ConstantValue::makeBool(ctx, b);
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));

    return true;
}

bool Cast::foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    auto& ctx = sema.ctx();

    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src     = sema.cstMgr().get(castCtx.constantFoldingSrc());
    ApsInt               value   = src.getIntLike();

    const uint32_t targetBits     = dstType.payloadIntLikeBits();
    const bool     targetUnsigned = dstType.isIntLikeUnsigned();
    const uint32_t valueBits      = value.bitWidth();

    const uint32_t checkBits = (valueBits > targetBits + 1) ? valueBits : (targetBits + 1);
    bool           overflow  = false;

    if (targetUnsigned)
    {
        if (!value.isUnsigned() && value.isNegative() && !castCtx.flags.has(CastFlagsE::NoOverflow) && targetBits != 0 && castCtx.kind != CastKind::Promotion)
        {
            castCtx.fail(DiagnosticId::sema_err_signed_unsigned, srcTypeRef, dstTypeRef, value.toString(), DiagnosticId::sema_note_signed_unsigned);
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
                    castCtx.fail(DiagnosticId::sema_err_signed_unsigned, srcTypeRef, dstTypeRef, value.toString(), DiagnosticId::sema_note_unsigned_signed);
                    return false;
                }
            }
        }
    }

    if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
    {
        castCtx.fail(DiagnosticId::sema_err_literal_overflow, srcTypeRef, dstTypeRef, value.toString());
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
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool Cast::foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType    = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src        = sema.cstMgr().get(castCtx.constantFoldingSrc());
    const ApsInt         intVal     = src.getIntLike();
    const uint32_t       targetBits = dstType.payloadFloatBits();

    ApFloat value;
    bool    isExact  = false;
    bool    overflow = false;
    value.set(intVal, targetBits, isExact, overflow);

    if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
    {
        castCtx.fail(DiagnosticId::sema_err_literal_overflow, srcTypeRef, dstTypeRef, intVal.toString());
        return false;
    }

    const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool Cast::foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src     = sema.cstMgr().get(castCtx.constantFoldingSrc());
    const ApFloat&       srcVal  = src.getFloat();

    const uint32_t targetBits = dstType.payloadIntLikeBits();
    const bool     isUnsigned = dstType.isIntLikeUnsigned();

    bool         isExact  = false;
    bool         overflow = false;
    const ApsInt value    = srcVal.toInt(targetBits, isUnsigned, isExact, overflow);

    if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
    {
        castCtx.fail(DiagnosticId::sema_err_literal_overflow, srcTypeRef, dstTypeRef, srcVal.toString());
        return false;
    }

    const ConstantValue result = ConstantValue::makeFromIntLike(ctx, value, dstType);
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
    return true;
}

bool Cast::foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const auto& ctx = sema.ctx();

    const TypeInfo&      dstType    = sema.typeMgr().get(dstTypeRef);
    const ConstantValue& src        = sema.cstMgr().get(castCtx.constantFoldingSrc());
    const ApFloat&       floatVal   = src.getFloat();
    const uint32_t       targetBits = dstType.payloadFloatBits();

    bool          isExact  = false;
    bool          overflow = false;
    const ApFloat value    = floatVal.toFloat(targetBits, isExact, overflow);

    if (overflow && !castCtx.flags.has(CastFlagsE::NoOverflow))
    {
        castCtx.fail(DiagnosticId::sema_err_literal_overflow, srcTypeRef, dstTypeRef, floatVal.toString());
        return false;
    }

    const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
    castCtx.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, result));
    return true;
}

Result Cast::castConstant(Sema& sema, ConstantRef& result, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef)
{
    const ConstantValue& cst        = sema.cstMgr().get(cstRef);
    const TypeRef        srcTypeRef = cst.typeRef();
    castCtx.srcConstRef             = cstRef;

    const auto res = castAllowed(sema, castCtx, srcTypeRef, targetTypeRef);
    if (res != Result::Continue)
    {
        if (res == Result::Error)
            return emitCastFailure(sema, castCtx.failure);
        return res;
    }

    result = castCtx.outConstRef;
    return Result::Continue;
}

Result Cast::castConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeRef targetTypeRef, AstNodeRef errorNodeRef, CastKind castKind)
{
    CastContext castCtx(castKind);
    castCtx.errorNodeRef = errorNodeRef;
    return castConstant(sema, result, castCtx, cstRef, targetTypeRef);
}

Result Cast::promoteConstants(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts)
{
    TypeRef leftTypeRef  = nodeLeftView.typeRef;
    TypeRef rightTypeRef = nodeRightView.typeRef;
    if (!force32BitInts && leftTypeRef == rightTypeRef)
        return Result::Continue;

    const TypeInfo* leftType  = nodeLeftView.type;
    const TypeInfo* rightType = nodeRightView.type;
    SWC_ASSERT(leftType->isScalarNumeric() && rightType->isScalarNumeric());

    const bool leftConcrete  = leftType->isConcreteScalar();
    const bool rightConcrete = rightType->isConcreteScalar();

    leftCstRef  = nodeLeftView.cstRef;
    rightCstRef = nodeRightView.cstRef;

    // If one side is concrete, concretize the other side.
    // If both sides are not concrete, keep it that way to concretize at the very last moment.
    if (leftConcrete != rightConcrete)
    {
        if (!leftConcrete)
        {
            const TypeInfo::Sign hintSign = rightType->isInt() ? rightType->payloadIntSign() : TypeInfo::Sign::Signed;
            RESULT_VERIFY(sema.cstMgr().concretizeConstant(sema, leftCstRef, nodeLeftView.nodeRef, leftCstRef, hintSign));
            leftTypeRef = sema.cstMgr().get(leftCstRef).typeRef();
        }
        else if (!rightConcrete)
        {
            const TypeInfo::Sign hintSign = leftType->isInt() ? leftType->payloadIntSign() : TypeInfo::Sign::Signed;
            RESULT_VERIFY(sema.cstMgr().concretizeConstant(sema, rightCstRef, nodeRightView.nodeRef, rightCstRef, hintSign));
            rightTypeRef = sema.cstMgr().get(rightCstRef).typeRef();
        }
    }

    const TypeRef promotedTypeRef = sema.typeMgr().promote(leftTypeRef, rightTypeRef, force32BitInts);
    RESULT_VERIFY(castConstant(sema, leftCstRef, leftCstRef, promotedTypeRef, nodeLeftView.nodeRef, CastKind::Promotion));
    RESULT_VERIFY(castConstant(sema, rightCstRef, rightCstRef, promotedTypeRef, nodeRightView.nodeRef, CastKind::Promotion));

    return Result::Continue;
}

SWC_END_NAMESPACE();
