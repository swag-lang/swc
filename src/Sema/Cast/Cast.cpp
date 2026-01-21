#include "pch.h"
#include "Sema/Cast/Cast.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = srcRef;
    dstTypeRef = dstRef;
    valueStr   = std::string(value);
    noteId     = note;
}

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
}

namespace
{
    Result castIdentity(Sema&, CastContext& castCtx, TypeRef, TypeRef)
    {
        if (castCtx.isConstantFolding())
            Cast::foldConstantIdentity(castCtx);
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
            srcTypeRef = srcType->symEnum().underlyingTypeRef();
            srcType    = &typeMgr.get(srcTypeRef);
            if (castCtx.isConstantFolding())
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

            return Result::Error;
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

            return Result::Error;
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantBitCast(sema, castCtx, dstTypeRef, dstType, *srcType))
                return Result::Error;
        }

        return Result::Continue;
    }

    Result castBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantBoolToIntLike(sema, castCtx, dstTypeRef))
                return Result::Error;
        }

        return Result::Continue;
    }

    Result castToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit && castCtx.kind != CastKind::Condition)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        const auto&     typeMgr = sema.ctx().typeMgr();
        const TypeInfo& srcType = typeMgr.get(srcTypeRef);
        if (!srcType.isIntLike() &&
            !srcType.isAnyPointer() &&
            !srcType.isInterface() &&
            !srcType.isLambdaClosure() &&
            !srcType.isSlice())
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        if (castCtx.isConstantFolding())
        {
            if (srcType.isIntLike())
            {
                if (!Cast::foldConstantIntLikeToBool(sema, castCtx))
                    return Result::Error;
            }
            else
                SWC_UNREACHABLE();
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
                        return Result::Error;
                    }
                }
                else
                {
                    if (!(srcType.isInt() && dstType.isInt()))
                    {
                        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                        return Result::Error;
                    }
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Parameter:
            case CastKind::Initialization:
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Error;
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
                    return Result::Error;
                }
                break;

            case CastKind::Promotion:
            case CastKind::Implicit:
            case CastKind::Parameter:
            case CastKind::Initialization:
            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Error;
        }

        return Result::Continue;
    }

    Result castFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Error;
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
            case CastKind::Parameter:
            case CastKind::Initialization:
                if (narrowing)
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                    return Result::Error;
                }
                break;

            case CastKind::Explicit:
                break;

            default:
                SWC_UNREACHABLE();
        }

        if (castCtx.isConstantFolding())
        {
            if (!Cast::foldConstantFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef))
                return Result::Error;
        }

        return Result::Continue;
    }

    Result castFromEnum(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.kind != CastKind::Explicit)
        {
            castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            return Result::Error;
        }

        const TypeInfo&   type    = sema.typeMgr().get(srcTypeRef);
        const SymbolEnum& enumSym = type.symEnum();

        if (castCtx.isConstantFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castCtx.srcConstRef);
            castCtx.srcConstRef      = cst.getEnumValue();
        }

        const auto res = Cast::castAllowed(sema, castCtx, enumSym.underlyingTypeRef(), dstTypeRef);
        if (res != Result::Continue)
        {
            castCtx.failure.srcTypeRef = srcTypeRef;
            castCtx.failure.noteId     = DiagnosticId::sema_err_enum_underlying_cast;
            castCtx.failure.optTypeRef = enumSym.underlyingTypeRef();
            return res;
        }

        return Result::Continue;
    }

    Result castFromNull(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isPointerLike())
        {
            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castFromUndefined(Sema&, CastContext& castCtx, TypeRef, TypeRef)
    {
        if (castCtx.isConstantFolding())
            castCtx.outConstRef = castCtx.srcConstRef;
        return Result::Continue;
    }

    Result castToReference(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        const auto  dstPointeeTypeRef = dstType.typeRef();
        const auto& dstPointeeType    = sema.typeMgr().get(dstPointeeTypeRef);

        // Ref to ref
        if (srcType.isReference())
        {
            if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            const auto  srcPointeeTypeRef = srcType.typeRef();
            const auto& srcPointeeType    = sema.typeMgr().get(srcPointeeTypeRef);

            if (srcPointeeTypeRef == dstPointeeTypeRef)
            {
                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }

            // Struct ref to interface ref
            if (srcPointeeType.isStruct() && dstPointeeType.isInterface())
            {
                const auto& fromStruct = srcPointeeType.symStruct();
                const auto& toItf      = dstPointeeType.symInterface();
                bool        ok         = false;
                for (const auto itfImpl : fromStruct.interfaces())
                {
                    if (itfImpl && itfImpl->idRef() == toItf.idRef())
                    {
                        ok = true;
                        break;
                    }
                }

                if (ok)
                {
                    if (castCtx.isConstantFolding())
                        castCtx.outConstRef = castCtx.srcConstRef;
                    return Result::Continue;
                }
            }
        }

        // Pointer to ref
        if (srcType.isAnyPointer())
        {
            if (srcType.isNullable())
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (srcType.typeRef() == dstPointeeTypeRef)
            {
                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }
        }

        // Value to const ref
        if (srcType.isStruct() && dstType.isConst())
        {
            if (dstPointeeTypeRef == srcTypeRef)
            {
                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }
        }

        // UFCS receiver: allow taking the address to bind a value to a reference.
        // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
        if (castCtx.flags.has(CastFlagsE::UfcsArgument) && dstPointeeTypeRef == srcTypeRef)
        {
            if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castPointerToPointer(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        const bool sameUnderlying = srcType.typeRef() == dstType.typeRef();
        const bool dstIsVoid      = dstType.typeRef() == sema.typeMgr().typeVoid();
        if (sameUnderlying || dstIsVoid || castCtx.kind == CastKind::Explicit)
        {
            bool ok = false;
            if (srcType.kind() == dstType.kind())
                ok = true;
            else if (srcType.isBlockPointer() && dstType.isValuePointer())
                ok = true;
            else if (srcType.isValuePointer() && dstType.isBlockPointer() && castCtx.kind == CastKind::Explicit)
                ok = true;
            // TODO
            // @compatibility
            else if (sameUnderlying && dstIsVoid)
                ok = true;

            if (ok)
            {
                // TODO
                // @compatibility
                if (dstType.ultimateTypeRef(sema.ctx()) == sema.typeMgr().typeVoid())
                {
                }
                else if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                    return Result::Error;
                }

                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castToPointer(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        // UFCS receiver: allow taking the address to get a pointer.
        // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
        if (castCtx.flags.has(CastFlagsE::UfcsArgument) && dstType.typeRef() == srcTypeRef && !dstType.isNullable())
        {
            if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        if (srcType.isAnyPointer())
            return castPointerToPointer(sema, castCtx, srcTypeRef, dstTypeRef);

        if (srcTypeRef == sema.ctx().typeMgr().typeU64())
        {
            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        if (srcType.isArray())
        {
            const auto srcElemTypeRef = srcType.arrayElemTypeRef();
            const auto dstElemTypeRef = dstType.typeRef();

            if (castCtx.kind == CastKind::Explicit ||
                srcElemTypeRef == dstElemTypeRef ||
                dstElemTypeRef == sema.typeMgr().typeVoid())
            {
                if (srcType.isConst() && !dstType.isConst() && !castCtx.flags.has(CastFlagsE::UnConst))
                {
                    castCtx.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
                    return Result::Error;
                }

                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castFromTypeValue(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto& dstType = sema.typeMgr().get(dstTypeRef);
        if (dstType.isTypeInfo() || dstType.isConstPointerToAnyTypeInfo(sema.ctx()))
        {
            if (castCtx.isConstantFolding())
            {
                const auto cst = sema.cstMgr().get(castCtx.srcConstRef);
                RESULT_VERIFY(sema.cstMgr().makeConstantTypeInfo(sema, castCtx.outConstRef, cst.getTypeValue(), castCtx.errorNodeRef));
            }

            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castToFromTypeInfo(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (castCtx.isConstantFolding())
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
                return Result::Error;
            }

            if (srcType.typeRef() != typeMgr.typeU8())
            {
                castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
                return Result::Error;
            }

            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castToCString(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto& typeMgr = sema.ctx().typeMgr();
        const auto& srcType = typeMgr.get(srcTypeRef);

        if (srcType.isBlockPointer())
        {
            if (srcType.typeRef() == sema.typeMgr().typeU8())
            {
                if (castCtx.isConstantFolding())
                    castCtx.outConstRef = castCtx.srcConstRef;
                return Result::Continue;
            }
        }

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    Result castToVariadic(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        const auto& typeMgr = sema.ctx().typeMgr();
        const auto& dstType = typeMgr.get(dstTypeRef);

        if (dstType.isVariadic())
        {
            if (castCtx.isConstantFolding())
                castCtx.outConstRef = castCtx.srcConstRef;
            return Result::Continue;
        }

        if (dstType.isTypedVariadic())
            return Cast::castAllowed(sema, castCtx, srcTypeRef, dstType.typeRef());

        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }
}

TypeRef Cast::castAllowedBothWays(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castAllowed(sema, castCtx, srcTypeRef, dstTypeRef) == Result::Continue)
        return dstTypeRef;
    if (castAllowed(sema, castCtx, dstTypeRef, srcTypeRef) == Result::Continue)
        return srcTypeRef;
    return TypeRef::invalid();
}

TypeRef Cast::castAllowedBothWays(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastKind castKind)
{
    CastContext castCtx(castKind);
    return castAllowedBothWays(sema, castCtx, srcTypeRef, dstTypeRef);
}

Result Cast::castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef)
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
            return Result::Error;
        }
    }

    auto res = Result::Error;
    if (srcType.isAlias())
        res = castAllowed(sema, castCtx, srcType.symAlias().underlyingTypeRef(), dstTypeRef);
    else if (dstType.isAlias())
        res = castAllowed(sema, castCtx, srcTypeRef, dstType.symAlias().underlyingTypeRef());
    else if (castCtx.flags.has(CastFlagsE::BitCast))
        res = castBit(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isEnum() && !dstType.isEnum())
        res = castFromEnum(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isNull())
        res = castFromNull(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isUndefined())
        res = castFromUndefined(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isBool() && dstType.isIntLike())
        res = castBoolToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isBool())
        res = castToBool(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isIntLike() && dstType.isIntLike())
        res = castIntLikeToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isIntLike() && dstType.isFloat())
        res = castIntLikeToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isFloat() && dstType.isFloat())
        res = castFloatToFloat(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isFloat() && dstType.isIntLike())
        res = castFloatToIntLike(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isTypeValue())
        res = castFromTypeValue(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isTypeInfo() && dstType.isConstPointerToAnyTypeInfo(sema.ctx()))
        res = castToFromTypeInfo(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (srcType.isConstPointerToAnyTypeInfo(sema.ctx()) && dstType.isTypeInfo())
        res = castToFromTypeInfo(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyPointer())
        res = castToPointer(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isReference())
        res = castToReference(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyVariadic())
        res = castToVariadic(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isString())
        res = castToString(sema, castCtx, srcTypeRef, dstTypeRef);
    else if (dstType.isCString())
        res = castToCString(sema, castCtx, srcTypeRef, dstTypeRef);
    else
    {
        castCtx.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
        return Result::Error;
    }

    if (res == Result::Continue && castCtx.isConstantFolding())
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

Result Cast::cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags)
{
    CastKind  effectiveKind  = castKind;
    CastFlags effectiveFlags = castFlags;

    // `cast()` is an explicit user request to allow explicit casts later when the destination type becomes known.
    // Therefore, when we are about to apply a contextual cast on an `AutoCastExpr`, force the cast to be explicit
    // and apply its modifiers.
    if (const auto* autoCast = sema.ast().node(view.nodeRef).safeCast<AstAutoCastExpr>())
    {
        effectiveKind = CastKind::Explicit;
        if (autoCast->modifierFlags.has(AstModifierFlagsE::Bit))
            effectiveFlags.add(CastFlagsE::BitCast);
        if (autoCast->modifierFlags.has(AstModifierFlagsE::UnConst))
            effectiveFlags.add(CastFlagsE::UnConst);
    }

    if (view.typeRef == dstTypeRef && effectiveFlags == CastFlagsE::Zero)
        return Result::Continue;

    CastContext castCtx(effectiveKind);
    castCtx.flags        = effectiveFlags;
    castCtx.errorNodeRef = view.nodeRef;
    castCtx.setConstantFoldingSrc(view.cstRef);

    const Result result = castAllowed(sema, castCtx, view.typeRef, dstTypeRef);
    if (result == Result::Pause)
        return result;

    if (result == Result::Continue)
    {
        if (castCtx.constantFoldingResult().isInvalid())
            view.nodeRef = createImplicitCast(sema, dstTypeRef, view.nodeRef);
        else
        {
            view.setCstRef(sema, castCtx.constantFoldingResult());
            sema.setConstant(view.nodeRef, castCtx.constantFoldingResult());
        }

        return Result::Continue;
    }

    if (effectiveKind != CastKind::Explicit)
    {
        CastContext explicitCtx(CastKind::Explicit);
        explicitCtx.errorNodeRef = view.nodeRef;
        if (castAllowed(sema, explicitCtx, view.typeRef, dstTypeRef) == Result::Continue)
            castCtx.failure.noteId = DiagnosticId::sema_note_cast_explicit;
    }

    return emitCastFailure(sema, castCtx.failure);
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
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
    return Result::Error;
}

AstNodeRef Cast::createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef)
{
    SemaInfo&      semaInfo           = sema.semaInfo();
    const AstNode& node               = sema.ast().node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(node.tokRef());
    substNodePtr->nodeExprRef         = nodeRef;
    semaInfo.setSubstitute(nodeRef, substNodeRef);
    semaInfo.setType(substNodeRef, dstTypeRef);
    SemaInfo::setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
