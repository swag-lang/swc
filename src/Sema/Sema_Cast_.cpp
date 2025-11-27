#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

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
            break;
    }

    const AstNode& nodeLiteralPtr = node(castCtx.errorNode);
    auto           diag           = reportError(DiagnosticId::sema_err_cannot_cast, nodeLiteralPtr.srcViewRef(), nodeLiteralPtr.tokRef());
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
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
        const AstNode& nodeLiteralPtr = node(castCtx.errorNode);
        auto           diag           = reportError(DiagnosticId::sema_err_literal_overflow, nodeLiteralPtr.srcViewRef(), nodeLiteralPtr.tokRef());
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

SWC_END_NAMESPACE()
