// ReSharper disable CppClangTidyClangDiagnosticMissingDesignatedFieldInitializers
#include "pch.h"
#include "Sema/Type/SemaCast.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"
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
        SWC_ASSERT(castCtx.kind == CastKind::Explicit);

        auto&              ctx     = sema.ctx();
        const TypeManager& typeMgr = ctx.typeMgr();
        const TypeInfo*    srcType = &typeMgr.get(srcTypeRef);
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

        // In the case of an enum, we must take the underlying type
        const bool    isEnum        = srcType->isEnum();
        const TypeRef orgSrcTypeRef = srcTypeRef;
        if (isEnum)
        {
            srcTypeRef = srcType->enumSym().underlyingTypeRef();
            srcType    = &typeMgr.get(srcTypeRef);
            if (castCtx.isFolding())
            {
                const ConstantValue& cst = sema.cstMgr().get(castCtx.srcConstRef);
                castCtx.srcConstRef      = cst.getEnumValue();
            }
        }

        const bool srcScalar = srcType->isScalarNumeric();
        const bool dstScalar = dstType.isScalarNumeric();
        if (!srcScalar || !dstScalar)
        {
            castCtx.fail(DiagnosticId::sema_err_bit_cast_invalid_type, orgSrcTypeRef, dstTypeRef);
            if (isEnum)
            {
                castCtx.failure.noteId     = DiagnosticId::sema_err_enum_underlying_cast;
                castCtx.failure.optTypeRef = srcTypeRef;
            }

            return false;
        }

        const uint32_t sb = srcType->scalarNumericBits();
        const uint32_t db = dstType.scalarNumericBits();
        if (!(sb == db || !sb))
        {
            castCtx.fail(DiagnosticId::sema_err_bit_cast_size, orgSrcTypeRef, dstTypeRef);
            if (isEnum)
            {
                castCtx.failure.noteId     = DiagnosticId::sema_err_enum_underlying_cast;
                castCtx.failure.optTypeRef = srcTypeRef;
            }

            return false;
        }

        if (castCtx.isFolding())
            return SemaCast::foldConstantBitCast(sema, castCtx, dstTypeRef, dstType, *srcType);

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

    bool castFromEnum(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return false;
        }

        const TypeInfo&   type    = sema.typeMgr().get(srcTypeRef);
        const SymbolEnum& enumSym = type.enumSym();

        if (castCtx.isFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castCtx.srcConstRef);
            castCtx.srcConstRef      = cst.getEnumValue();
        }

        const bool ok = SemaCast::castAllowed(sema, castCtx, enumSym.underlyingTypeRef(), dstTypeRef);
        if (!ok)
        {
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.noteId     = DiagnosticId::sema_err_enum_underlying_cast;
            castCtx.failure.optTypeRef = enumSym.underlyingTypeRef();
        }

        return ok;
    }
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
    if (srcType.isEnum() && !dstType.isEnum())
        return castFromEnum(sema, castCtx, srcTypeRef, dstTypeRef);

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

Result SemaCast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    auto diag = SemaError::report(sema, f.diagId, f.nodeRef);
    if (f.srcTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_TYPE, f.srcTypeRef);
    if (f.dstTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, f.dstTypeRef);
    if (f.optTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_OPT_TYPE, f.optTypeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, f.valueStr);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Stop;
}

AstNodeRef SemaCast::createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef)
{
    SemaInfo&      semaInfo           = sema.semaInfo();
    const AstNode& node               = sema.ast().node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(node.tokRef());
    substNodePtr->nodeExprRef         = nodeRef;
    semaInfo.setSubstitute(nodeRef, substNodeRef);
    semaInfo.setType(substNodeRef, dstTypeRef);
    return substNodeRef;
}

SWC_END_NAMESPACE()
