// ReSharper disable CppClangTidyClangDiagnosticMissingDesignatedFieldInitializers
#include "pch.h"
#include "Sema/Type/SemaCast.h"
#include "Report/Diagnostic.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Sema.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    bool castOpIdentity(Sema&, const CastContext& castCtx, TypeRef, TypeRef)
    {
        if (castCtx.isFolding())
            SemaCast::foldConstantIdentity(castCtx);
        return true;
    }

    bool castOpBitCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

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

        if (castCtx.isFolding())
            return SemaCast::foldConstantBitCast(sema, castCtx, dstTypeRef, dstType, srcType);

        return true;
    }

    bool castOpBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantBoolToIntLike(sema, castCtx, dstType);

        return true;
    }

    bool castOpIntLikeToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isBool())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToBool(sema, castCtx);

        return true;
    }

    bool castOpIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef, dstType);

        return true;
    }

    bool castOpIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isFloat())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef, dstType);

        return true;
    }

    bool castOpFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isIntLike())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef, dstType);

        return true;
    }

    bool castOpFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.ctx().typeMgr().get(dstTypeRef);

        if (!dstType.isFloat())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef, dstType);

        return true;
    }
}

bool SemaCast::analyseCastCore(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    castCtx.resetFailure();

    if (castCtx.fold && castCtx.fold->outConstRef)
        *castCtx.fold->outConstRef = ConstantRef::invalid();

    const auto&     typeMgr = sema.ctx().typeMgr();
    const TypeInfo& src     = typeMgr.get(srcTypeRef);
    const TypeInfo& dst     = typeMgr.get(dstTypeRef);

    if (srcTypeRef == dstTypeRef)
        return castOpIdentity(sema, castCtx, srcTypeRef, dstTypeRef);

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

    if (castCtx.flags.has(CastFlagsE::BitCast))
        return castOpBitCast(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isBool() && dst.isIntLike())
        return castOpBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isIntLike() && dst.isBool())
        return castOpIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isIntLike() && dst.isIntLike())
        return castOpIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isIntLike() && dst.isFloat())
        return castOpIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isFloat() && dst.isFloat())
        return castOpFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (src.isFloat() && dst.isIntLike())
        return castOpFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);

    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    return false;
}

bool SemaCast::analyseCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    CastFoldContext* saved = castCtx.fold;
    castCtx.fold           = nullptr;
    const bool ok          = analyseCastCore(sema, castCtx, srcTypeRef, dstTypeRef);
    castCtx.fold           = saved;
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

SWC_END_NAMESPACE()
