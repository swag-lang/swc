#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaNodeView.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef castCharToInt(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&               ctx        = sema.ctx();
        const TypeManager&  typeMgr    = ctx.typeMgr();
        const TypeInfo&     targetType = typeMgr.get(targetTypeRef);
        const ApsInt        value(src.getChar(), targetType.intBits(), true);
        const ConstantValue result = ConstantValue::makeInt(ctx, value, targetType.intBits());
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castIntToChar(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&               ctx    = sema.ctx();
        const ConstantValue result = ConstantValue::makeChar(ctx, static_cast<uint32_t>(src.getInt().asU64()));
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castIntToInt(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

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

        const ConstantValue result = ConstantValue::makeInt(ctx, value, targetBits);
        return ctx.cstMgr().addConstant(ctx, result);
    }

    ConstantRef castIntToFloat(Sema& sema, const CastContext& castCtx, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
        const ApsInt&      intVal     = src.getInt();
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

    ConstantRef castFloatToFloat(Sema& sema, const CastContext&, const ConstantValue& src, TypeRef targetTypeRef)
    {
        auto&              ctx        = sema.ctx();
        const TypeManager& typeMgr    = ctx.typeMgr();
        const TypeInfo&    targetType = typeMgr.get(targetTypeRef);
        const ApFloat&     floatVal   = src.getFloat();
        const uint32_t     targetBits = targetType.floatBits();

        ApFloat value;
        switch (targetBits)
        {
            case 32:
                value.set(floatVal.asFloat());
                break;
            case 64:
                value.set(floatVal.asDouble());
                break;
            default:
                SWC_UNREACHABLE();
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

    auto&              ctx        = *ctx_;
    const TypeManager& typeMgr    = ctx.typeMgr();
    const TypeInfo&    srcType    = typeMgr.get(src.typeRef());
    const TypeInfo&    targetType = typeMgr.get(targetTypeRef);

    if (srcType.isChar())
        return castCharToInt(*this, castCtx, src, targetTypeRef);
    if (targetType.isChar())
        return castIntToChar(*this, castCtx, src, targetTypeRef);
    if (srcType.isInt() && targetType.isInt())
        return castIntToInt(*this, castCtx, src, targetTypeRef);
    if (srcType.isInt() && targetType.isFloat())
        return castIntToFloat(*this, castCtx, src, targetTypeRef);
    if (srcType.isFloat() && targetType.isFloat())
        return castFloatToFloat(*this, castCtx, src, targetTypeRef);

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
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    const SemaNodeView nodeExprView(sema, nodeExprRef);

    CastContext castCtx;
    castCtx.kind         = CastKind::Explicit;
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
