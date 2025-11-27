#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"
#include <mimalloc/types.h>

SWC_BEGIN_NAMESPACE()

bool Sema::castAllowed(const CastContext& castCtx, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef)
{
    auto&       ctx        = *ctx_;
    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& srcType    = typeMgr.get(srcTypeRef);
    const auto& targetType = typeMgr.get(targetTypeRef);

    switch (castCtx.kind)
    {
        case CastKind::LiteralSuffix:
            if (srcType.isInt() && targetType.isInt())
                return true;
            if (srcType.isInt() && targetType.isFloat())
                return true;
            break;

        default:
            SWC_UNREACHABLE();
    }

    auto diag = reportError(DiagnosticId::sema_err_cannot_cast, castCtx.errorNode);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx);
    return false;
}

ConstantRef Sema::cast(const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
{
    if (!castAllowed(castCtx, src.typeRef(), targetTypeRef))
        return ConstantRef::invalid();

    auto&       ctx        = *ctx_;
    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& srcType    = typeMgr.get(src.typeRef());
    const auto& targetType = typeMgr.get(targetTypeRef);

    if (srcType.isInt() && targetType.isInt())
        return castIntToInt(castCtx, src, targetTypeRef);
    if (srcType.isInt() && targetType.isFloat())
        return castIntToFloat(castCtx, src, targetTypeRef);

    raiseInternalError(node(castCtx.errorNode));
    return ConstantRef::invalid();
}

ConstantRef Sema::castIntToInt(const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
{
    auto& ctx = *ctx_;
    SWC_ASSERT(src.isInt());

    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& targetType = typeMgr.get(targetTypeRef);

    // We only support integer target types here
    SWC_ASSERT(targetType.isInt());

    const uint32_t targetBits     = targetType.intBits();
    const bool     targetSigned   = targetType.isIntSigned();
    const bool     targetUnsigned = !targetSigned;

    // Make a working copy of the integer value
    ApsInt value = src.getInt();

    // Create a copy for overflow checking with the SOURCE signedness
    ApsInt valueForCheck = value;

    // Set the target signedness for comparison
    if (valueForCheck.isUnsigned() != targetUnsigned)
        valueForCheck.setUnsigned(targetUnsigned);

    // Get min/max values for the target type
    const ApsInt minVal = ApsInt::minValue(targetBits, targetUnsigned);
    const ApsInt maxVal = ApsInt::maxValue(targetBits, targetUnsigned);

    // Extend valueForCheck to match the bit width for comparison
    // This ensures we can properly compare against min/max without truncation
    const uint32_t sourceBits = valueForCheck.bitWidth();
    if (sourceBits < targetBits)
    {
        valueForCheck.resize(targetBits);
    }

    // Also extend min/max to the source bit width if needed for comparison
    ApsInt minValExtended = minVal;
    ApsInt maxValExtended = maxVal;
    bool   overflow       = false;
    if (targetBits < sourceBits)
    {
        minValExtended.resize(sourceBits);
        maxValExtended.resize(sourceBits);
        overflow = (valueForCheck < minValExtended || valueForCheck > maxValExtended);
    }
    else
    {
        overflow = (valueForCheck < minVal || valueForCheck > maxVal);
    }

    if (overflow)
    {
        auto diag = reportError(DiagnosticId::sema_err_literal_overflow, castCtx.errorNode);
        diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
        diag.report(ctx);
        return ConstantRef::invalid();
    }

    // Now normalize to the target representation
    if (value.isUnsigned() != targetUnsigned)
        value.setUnsigned(targetUnsigned);

    // Finally, adjust the bit width to the target (this may wrap if overflow == true)
    value.resize(targetBits);

    // Build the resulting constant with the *target* integer type
    const ConstantValue result = ConstantValue::makeApsInt(ctx, value, targetBits);
    return ctx.compiler().constMgr().addConstant(ctx, result);
}

ConstantRef Sema::castIntToFloat(const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
{
    auto& ctx = *ctx_;
    SWC_ASSERT(src.isInt());

    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& targetType = typeMgr.get(targetTypeRef);
    SWC_ASSERT(targetType.isFloat());

    const ApsInt&  intVal     = src.getInt();
    const uint32_t targetBits = targetType.floatBits();

    bool    precisionLoss = false;
    ApFloat value;

    // Convert integer to floating point
    if (intVal.isUnsigned())
    {
        // For unsigned, convert directly
        if (intVal.fits64())
        {
            value.set(static_cast<double>(intVal.to64()));
        }
        else
        {
            // For very large integers, there will be precision loss
            precisionLoss = true;
            // Convert word by word (simplified - may need better handling)
            value.set(static_cast<double>(intVal.to64()));
        }
    }
    else
    {
        // For signed, check sign bit
        if (intVal.isNegative())
        {
            // Get absolute value (simplified)
            ApsInt absVal = intVal;
            // TODO: Proper two's complement negation
            value.set(-static_cast<double>(absVal.to64()));
        }
        else
        {
            value.set(static_cast<double>(intVal.to64()));
        }
    }

    // Check for precision loss based on target float type
    if (targetBits == 32)
    {
        // f32 has 24 bits of precision
        const uint32_t intBits = intVal.bitWidth();
        if (intBits > 24)
        {
            // May have precision loss
            const float f32Val = value.toFloat();
            if (static_cast<double>(f32Val) != value.toDouble())
                precisionLoss = true;
        }

        value.set(static_cast<float>(value.toDouble()));
    }

    // f64 has 53 bits of precision
    else if (intVal.bitWidth() > 53)
    {
        precisionLoss = true;
    }

    // Build the resulting constant with the *target* integer type
    const ConstantValue result = ConstantValue::makeFloat(ctx, value, targetBits);
    return ctx.compiler().constMgr().addConstant(ctx, result);
}

SWC_END_NAMESPACE()
