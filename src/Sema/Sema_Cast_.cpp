#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef castIntToInt(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
    {
        auto& ctx = sema.ctx();
        SWC_ASSERT(src.isInt());

        const auto& typeMgr    = ctx.compiler().typeMgr();
        const auto& targetType = typeMgr.get(targetTypeRef);

        // We only support integer target types here
        SWC_ASSERT(targetType.isInt());

        // Working copy of the integer value (with SOURCE signedness)
        ApsInt value = src.getInt();

        const uint32_t targetBits     = targetType.intBits();
        const bool     targetUnsigned = targetType.isIntUnsigned();
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
                auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, castCtx.errorNodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
                diag.report(ctx);
                return ConstantRef::invalid();
            }

            // Compare in UNSIGNED space.
            ApsInt vCheck = value;
            if (!vCheck.isUnsigned())
                vCheck.setUnsigned(true); // reinterpret bits as unsigned

            vCheck.resize(checkBits); // zero-extend

            ApsInt maxCheck = ApsInt::maxValue(targetBits, true);
            maxCheck.resize(checkBits); // zero-extend

            if (vCheck > maxCheck)
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

                if (vCheck < minCheck || vCheck > maxCheck)
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

                if (vCheck > maxU)
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

        // Build the resulting constant with the *target* integer type
        const ConstantValue result = ConstantValue::makeInt(ctx, value, targetBits);
        return ctx.compiler().constMgr().addConstant(ctx, result);
    }

    ConstantRef castIntToFloat(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
    {
        auto& ctx = sema.ctx();
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
            if (!intVal.fits64())
                precisionLoss = true;
            value.set(static_cast<double>(intVal.asU64()));
        }
        else
        {
            // For signed, check sign bit
            if (intVal.isNegative())
            {
                // Get absolute value
                ApsInt absVal = intVal;

                bool overflow = false;
                absVal.abs(overflow);
                if (overflow)
                {
                    sema.raiseLiteralOverflow(castCtx.errorNodeRef, targetTypeRef);
                    return ConstantRef::invalid();
                }

                value.set(-static_cast<double>(absVal.asU64()));
            }
            else
            {
                value.set(static_cast<double>(intVal.asU64()));
            }
        }

        // Check for precision loss based on the target float type
        if (targetBits == 32)
        {
            // f32 has 24 bits of precision
            const uint32_t intBits = intVal.bitWidth();
            if (intBits > 24)
            {
                // May have precision loss
                const float f32Val = value.asFloat();
                if (static_cast<double>(f32Val) != value.asDouble())
                    precisionLoss = true;
            }

            value.set(static_cast<float>(value.asDouble()));
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

    ConstantRef castFloatToFloat(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeInfoRef targetTypeRef)
    {
        auto& ctx = sema.ctx();
        SWC_ASSERT(src.isFloat());

        return ConstantRef::invalid();
    }
}

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

    raiseCannotCast(castCtx.errorNodeRef, srcTypeRef, targetTypeRef);
    return false;
}

ConstantRef Sema::cast(const CastContext& castCtx, ConstantRef srcRef, TypeInfoRef targetTypeRef)
{
    const auto src = constMgr().get(srcRef);
    if (src.typeRef() == targetTypeRef)
        return srcRef;

    if (!castAllowed(castCtx, src.typeRef(), targetTypeRef))
        return ConstantRef::invalid();

    auto&       ctx        = *ctx_;
    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& srcType    = typeMgr.get(src.typeRef());
    const auto& targetType = typeMgr.get(targetTypeRef);

    if (srcType.isInt() && targetType.isInt())
        return castIntToInt(*this, castCtx, src, targetTypeRef);
    if (srcType.isInt() && targetType.isFloat())
        return castIntToFloat(*this, castCtx, src, targetTypeRef);
    if (srcType.isFloat() && targetType.isFloat())
        return castFloatToFloat(*this, castCtx, src, targetTypeRef);

    raiseInternalError(node(castCtx.errorNodeRef));
    return ConstantRef::invalid();
}

SWC_END_NAMESPACE()
