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

SWC_BEGIN_NAMESPACE();

namespace
{
    Result castIdentity(Sema&, CastContext& castCtx, TypeRef, TypeRef)
    {
        if (castCtx.isFolding())
            SemaCast::foldConstantIdentity(castCtx);
        return Result::Continue;
    }

    Result castBit(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
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

            return Result::Stop;
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

            return Result::Stop;
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantBitCast(sema, castCtx, dstTypeRef, dstType, *srcType))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Stop;
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantBoolToIntLike(sema, castCtx, dstTypeRef))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castIntLikeToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Stop;
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantIntLikeToBool(sema, castCtx))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
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
                        return Result::Stop;
                    }
                }
                else
                {
                    if (!(srcType.isInt() && dstType.isInt()))
                    {
                        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                        return Result::Stop;
                    }
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Initialization:
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);

        switch (castCtx.kind)
        {
            case CastKind::LiteralSuffix:
                if (!srcType.isIntUnsized())
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return Result::Stop;
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Initialization:
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Stop;
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
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
            case CastKind::Initialization:
                if (narrowing)
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return Result::Stop;
                }
                break;

            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isFolding())
        {
            if (!SemaCast::foldConstantFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Stop;
        }

        return Result::Continue;
    }

    Result castFromEnum(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Stop;
        }

        const TypeInfo&   type    = sema.typeMgr().get(srcTypeRef);
        const SymbolEnum& enumSym = type.enumSym();

        if (castCtx.isFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castCtx.srcConstRef);
            castCtx.srcConstRef      = cst.getEnumValue();
        }

        const auto res = SemaCast::castAllowed(sema, castCtx, enumSym.underlyingTypeRef(), dstTypeRef);
        if (res != Result::Continue)
        {
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.noteId     = DiagnosticId::sema_err_enum_underlying_cast;
            castCtx.failure.optTypeRef = enumSym.underlyingTypeRef();
            return res;
        }

        return Result::Continue;
    }

    Result castNull(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isPointerLike())
        {
            if (castCtx.isFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Stop;
    }

    Result castUndefined(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.isFolding())
            castCtx.outConstRef = castCtx.srcConstRef;
        return Result::Continue;
    }

    Result castPointer(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        const bool sameUnderlying = srcType.typeRef() == dstType.typeRef();
        if (sameUnderlying || castCtx.kind == CastKind::Explicit)
        {
            bool ok = false;
            if (srcType.kind() == dstType.kind())
                ok = true;
            else if (srcType.isBlockPointer() && dstType.isValuePointer())
                ok = true;
            else if (srcType.isValuePointer() && dstType.isBlockPointer() && castCtx.kind == CastKind::Explicit)
                ok = true;

            if (ok)
            {
                if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                    return Result::Stop;
                }

                if (castCtx.isFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;

                return Result::Continue;
            }
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Stop;
    }

    Result castTypeInfo(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.isFolding())
            castCtx.outConstRef = castCtx.srcConstRef;
        return Result::Continue;
    }

    Result castToString(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto& typeMgr = sema.ctx().typeMgr();
        const auto& srcType = typeMgr.get(srcTypeRef);
        if (srcType.isSlice())
        {
            if (castCtx.kind != CastKind::Explicit)
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Stop;
            }

            if (srcType.typeRef() != typeMgr.typeU8())
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Stop;
            }

            if (castCtx.isFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Stop;
    }
}

Result SemaCast::castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (srcTypeRef == dstTypeRef)
        return castIdentity(sema, castCtx, srcTypeRef, dstTypeRef);

    const auto&     typeMgr = sema.ctx().typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    if (srcType.isAlias() || dstType.isAlias())
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Stop;
        }
    }

    auto res = Result::Stop;
    if (srcType.isAlias())
        res = castAllowed(sema, castCtx, srcType.aliasSym().underlyingTypeRef(), dstTypeRef);
    else if (dstType.isAlias())
        res = castAllowed(sema, castCtx, srcTypeRef, dstType.aliasSym().underlyingTypeRef());
    else if (castCtx.flags.has(CastFlagsE::BitCast))
        res = castBit(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isEnum() && !dstType.isEnum())
        res = castFromEnum(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isNull())
        res = castNull(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isUndefined())
        res = castUndefined(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isBool() && dstType.isIntLike())
        res = castBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isIntLike() && dstType.isBool())
        res = castIntLikeToBool(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isIntLike() && dstType.isIntLike())
        res = castIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isIntLike() && dstType.isFloat())
        res = castIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isFloat() && dstType.isFloat())
        res = castFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isFloat() && dstType.isIntLike())
        res = castFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isPointer() && dstType.isPointer())
        res = castPointer(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isTypeInfo() && dstType.isConstPointerToRuntimeTypeInfo(sema.ctx()))
        res = castTypeInfo(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isConstPointerToRuntimeTypeInfo(sema.ctx()) && dstType.isTypeInfo())
        res = castTypeInfo(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isSlice() && dstType.isString())
        res = castToString(sema, castCtx, srcTypeRef, dstTypeRef);
    else
    {
        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Stop;
    }

    if (res == Result::Continue && castCtx.isFolding())
    {
        ConstantValue resCst = sema.cstMgr().get(castCtx.outConstRef);
        if (resCst.typeRef() != dstTypeRef)
        {
            resCst.setTypeRef(dstTypeRef);
            castCtx.outConstRef = sema.cstMgr().addConstant(sema.ctx(), resCst);
        }
    }

    return res;
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

SWC_END_NAMESPACE();
