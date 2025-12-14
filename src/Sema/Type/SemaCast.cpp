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

        // Kind rules: keep acceptance local to this op.
        // LiteralSuffix never allowed BitCast in the previous coarse rules.
        if (castCtx.kind == CastKind::LiteralSuffix)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        // Promotion / Implicit used to be scalar-numeric only.
        if (castCtx.kind == CastKind::Promotion || castCtx.kind == CastKind::Implicit)
        {
            if (!(srcType.isScalarNumeric() && dstType.isScalarNumeric()))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return false;
            }
        }

        // Explicit: this op only makes sense on scalar numeric anyway (validated below).

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

        // Kind rules: only Explicit allowed bool <-> intlike.
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

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

        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

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
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        // Kind rules
        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                if (srcType.isChar())
                {
                    if (!(dstType.isIntUnsigned() || dstType.isRune()))
                    {
                        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                        return false;
                    }
                }
                else
                {
                    if (!(srcType.isInt() && dstType.isInt()))
                    {
                        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                        return false;
                    }
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
                if (!(srcType.isScalarNumeric() && dstType.isScalarNumeric()))
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

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
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                if (!srcType.isInt())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
                if (!srcType.isScalarNumeric())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            case CastKind::Explicit:
                if (!srcType.isScalarNumeric())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            default:
                SWC_UNREACHABLE();
        }

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
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        if (castCtx.kind == CastKind::LiteralSuffix)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (!srcType.isScalarNumeric())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

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
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                if (!srcType.isFloat())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Explicit:
                if (!srcType.isScalarNumeric())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            default:
                SWC_UNREACHABLE();
        }

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

    if (srcTypeRef == dstTypeRef)
        return castOpIdentity(sema, castCtx, srcTypeRef, dstTypeRef);

    const auto&     typeMgr = sema.ctx().typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    if (castCtx.flags.has(CastFlagsE::BitCast))
        return castOpBitCast(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isBool() && dstType.isIntLike())
        return castOpBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isBool())
        return castOpIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isIntLike())
        return castOpIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isFloat())
        return castOpIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isFloat() && dstType.isFloat())
        return castOpFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isFloat() && dstType.isIntLike())
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
