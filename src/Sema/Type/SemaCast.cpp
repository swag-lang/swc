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
    bool castIdentity(Sema&, CastContext& castCtx, TypeRef, TypeRef)
    {
        if (castCtx.isFolding())
            SemaCast::foldConstantIdentity(castCtx);
        return true;
    }

    bool castBit(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        if (castCtx.kind == CastKind::LiteralSuffix)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.kind == CastKind::Promotion || castCtx.kind == CastKind::Implicit)
        {
            if (!(srcType.isScalarNumeric() && dstType.isScalarNumeric()))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return false;
            }
        }

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

    bool castBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantBoolToIntLike(sema, castCtx, dstTypeRef);

        return true;
    }

    bool castIntLikeToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToBool(sema, castCtx);

        return true;
    }

    bool castIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

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
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);

        return true;
    }

    bool castIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);

        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                if (!srcType.isIntUnsized())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return false;
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);

        return true;
    }

    bool castFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);

        return true;
    }

    bool castFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        const TypeInfo& dstType = typeMgr.get(dstTypeRef);

        const uint32_t sb        = srcType.floatBits();
        const uint32_t db        = dstType.floatBits();
        const bool     narrowing = db < sb;

        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                break;

            case CastKind::Promotion:
                break;

            case CastKind::Implicit:
                if (narrowing)
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

        if (castCtx.isFolding())
            return SemaCast::foldConstantFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);

        return true;
    }
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

bool SemaCast::castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (srcTypeRef == dstTypeRef)
        return castIdentity(sema, castCtx, srcTypeRef, dstTypeRef);

    const auto&     typeMgr = sema.ctx().typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    if (castCtx.flags.has(CastFlagsE::BitCast))
        return castBit(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isBool() && dstType.isIntLike())
        return castBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isBool())
        return castIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isIntLike())
        return castIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike() && dstType.isFloat())
        return castIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isFloat() && dstType.isFloat())
        return castFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    if (srcType.isFloat() && dstType.isIntLike())
        return castFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);

    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    return false;
}

SWC_END_NAMESPACE()
