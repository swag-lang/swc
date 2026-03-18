#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void setEnumUnderlyingCastNote(CastRequest& castRequest, TypeRef enumTypeRef, TypeRef underlyingTypeRef)
    {
        castRequest.failure.srcTypeRef = enumTypeRef;
        castRequest.failure.noteId     = DiagnosticId::sema_note_enum_underlying_cast;
        castRequest.failure.optTypeRef = underlyingTypeRef;
    }

    bool shouldRouteEnumViaUnderlying(const CastRequest& castRequest, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (!srcType.isEnum())
            return false;
        if (dstType.isEnum() && castRequest.kind != CastKind::Explicit)
            return false;
        if (dstType.isAny())
            return false;

        if (dstType.isBool() && castRequest.kind == CastKind::Condition)
            return false;

        return true;
    }

    Result retargetLiteralRuntimeStorageIfNeeded(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef.isInvalid() || dstTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        const bool      needsRetarget =
            (srcType.isAggregateArray() && dstType.isArray()) ||
            (srcType.isAggregateStruct() && dstType.isStruct());
        if (!needsRetarget)
            return Result::Continue;

        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (!payload || payload->runtimeStorageSym == nullptr)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(&dstType, nodeRef));
        payload->runtimeStorageSym->setTypeRef(dstTypeRef);
        return Result::Continue;
    }
}

Result Cast::castIdentity(const Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);
    if (castRequest.isConstantFolding())
        foldConstantIdentity(castRequest);
    return Result::Continue;
}

Result Cast::castBit(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_ASSERT(castRequest.kind == CastKind::Explicit);

    TaskContext&       ctx     = sema.ctx();
    const TypeManager& typeMgr = ctx.typeMgr();
    const TypeInfo*    srcType = &typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    // In the case of an enum, we must take the underlying type
    const bool    isEnum        = srcType->isEnum();
    const TypeRef orgSrcTypeRef = srcTypeRef;
    if (isEnum)
    {
        srcTypeRef = srcType->payloadSymEnum().underlyingTypeRef();
        srcType    = &typeMgr.get(srcTypeRef);
        if (castRequest.isConstantFolding())
        {
            const ConstantValue& cst = sema.cstMgr().get(castRequest.srcConstRef);
            castRequest.srcConstRef  = cst.getEnumValue();
        }
    }

    const bool srcScalar = srcType->isScalarNumeric();
    const bool dstScalar = dstType.isScalarNumeric();
    if (!srcScalar || !dstScalar)
    {
        const Result res = castRequest.fail(DiagnosticId::sema_err_bit_cast_invalid_type, orgSrcTypeRef, dstTypeRef);
        if (isEnum)
            setEnumUnderlyingCastNote(castRequest, orgSrcTypeRef, srcTypeRef);

        return res;
    }

    const uint32_t sb = srcType->payloadScalarNumericBits();
    const uint32_t db = dstType.payloadScalarNumericBits();
    if (!(sb == db || !sb))
    {
        const Result res = castRequest.fail(DiagnosticId::sema_err_bit_cast_size, orgSrcTypeRef, dstTypeRef);
        if (isEnum)
            setEnumUnderlyingCastNote(castRequest, orgSrcTypeRef, srcTypeRef);

        return res;
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantBitCast(sema, castRequest, dstTypeRef, dstType, *srcType))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castBoolToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantBoolToIntLike(sema, castRequest, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToBool(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit && castRequest.kind != CastKind::Condition)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    if (!srcType.isConvertibleToBool())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        const ConstantValue* cv = &sema.cstMgr().get(castRequest.constantFoldingSrc());
        if (srcType.isEnumFlags())
        {
            castRequest.setConstantFoldingSrc(cv->getEnumValue());
            cv = &sema.cstMgr().get(castRequest.constantFoldingSrc());
        }

        if (cv->isNull())
            castRequest.setConstantFoldingResult(sema.cstMgr().cstFalse());
        else if (srcType.isIntLike())
        {
            if (!foldConstantIntLikeToBool(sema, castRequest))
                return Result::Error;
        }
        else if (srcType.isEnumFlags())
        {
            if (!foldConstantIntLikeToBool(sema, castRequest))
                return Result::Error;
        }
        else if (srcType.isString())
        {
            castRequest.setConstantFoldingResult(cv->getString().data() ? sema.cstMgr().cstTrue() : sema.cstMgr().cstFalse());
        }
        else
            SWC_UNREACHABLE();
    }

    return Result::Continue;
}

Result Cast::castIntLikeToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);
    const uint32_t     srcBits = srcType.payloadIntLikeBits();
    const uint32_t     dstBits = dstType.payloadIntLikeBits();

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            if (srcType.isChar())
            {
                if (!(dstType.isIntUnsigned() || dstType.isRune()))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            else
            {
                if (!(srcType.isInt() && dstType.isInt()))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            break;

        case CastKind::Promotion:
        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (!castRequest.isConstantFolding() || castRequest.flags.has(CastFlagsE::FoldedTypedConst))
            {
                const bool srcUnsized = srcType.isIntUnsized();
                const bool dstUnsized = dstType.isIntUnsized();
                if (!srcUnsized && !dstUnsized && srcBits && dstBits && dstBits < srcBits)
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }
            break;
        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantIntLikeToIntLike(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castIntLikeToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr     = sema.typeMgr();
    const TypeInfo&    srcType     = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType     = typeMgr.get(dstTypeRef);
    const uint32_t     dstBits     = dstType.payloadFloatBits();
    const uint32_t     srcBits     = srcType.payloadIntLikeBits();
    const bool         srcIsInt    = srcType.isInt();
    const bool         coerceToF32 = srcIsInt && srcBits <= 32;
    const bool         coerceToF64 = srcIsInt;
    const bool         allowCoerce = (dstBits == 32) ? coerceToF32 : coerceToF64;

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            if (!srcType.isIntUnsized())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;

        case CastKind::Promotion:
        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (!allowCoerce)
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;
        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantIntLikeToFloat(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castFloatToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantFloatToIntLike(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);

    if (srcType.isBool())
        return castBoolToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike())
        return castIntLikeToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isFloat())
        return castFloatToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);

    if (castRequest.kind == CastKind::Explicit)
    {
        // From pointer
        if (srcType.isAnyPointer() && dstTypeRef == sema.typeMgr().typeU64())
        {
            if (castRequest.isConstantFolding())
            {
                if (!foldConstantPointerToIntLike(sema, castRequest, dstTypeRef))
                    return Result::Error;
            }
            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFloatToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    const uint32_t sb        = srcType.payloadFloatBits();
    const uint32_t db        = dstType.payloadFloatBits();
    const bool     narrowing = db < sb;

    switch (castRequest.kind)
    {
        case CastKind::LiteralSuffix:
            break;

        case CastKind::Promotion:
            break;

        case CastKind::Implicit:
        case CastKind::Parameter:
        case CastKind::Initialization:
        case CastKind::Assignment:
            if (narrowing)
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            break;

        case CastKind::Explicit:
            break;

        default:
            SWC_UNREACHABLE();
    }

    if (castRequest.isConstantFolding())
    {
        if (!foldConstantFloatToFloat(sema, castRequest, srcTypeRef, dstTypeRef))
            return Result::Error;
    }

    return Result::Continue;
}

Result Cast::castToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);

    if (srcType.isFloat())
        return castFloatToFloat(sema, castRequest, srcTypeRef, dstTypeRef);
    if (srcType.isIntLike())
        return castIntLikeToFloat(sema, castRequest, srcTypeRef, dstTypeRef);

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromEnum(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeInfo&   srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo&   dstType = sema.typeMgr().get(dstTypeRef);
    const SymbolEnum& enumSym = srcType.payloadSymEnum();

    // Only enum flags (or enums already backed by bool) can be cast to bool.
    if (dstType.isBool() && !srcType.isEnumFlags() && enumSym.underlyingTypeRef() != dstTypeRef)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (castRequest.isConstantFolding())
    {
        const ConstantValue& cst = sema.cstMgr().get(castRequest.srcConstRef);
        if (cst.isEnumValue())
            castRequest.srcConstRef = cst.getEnumValue();
    }

    const TypeRef dstUnderlyingTypeRef = dstType.isEnum() ? dstType.payloadSymEnum().underlyingTypeRef() : dstTypeRef;
    const auto    res                  = castAllowed(sema, castRequest, enumSym.underlyingTypeRef(), dstUnderlyingTypeRef);
    if (res != Result::Continue)
    {
        setEnumUnderlyingCastNote(castRequest, srcTypeRef, enumSym.underlyingTypeRef());
        return res;
    }

    return Result::Continue;
}

Result Cast::castFromNull(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (dstType.isPointerLike())
        return Result::Continue;

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromUndefined(const Sema& sema, const CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(castRequest);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);
    return Result::Continue;
}

Result Cast::castToReference(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    const auto      dstPointeeTypeRef = dstType.payloadTypeRef();
    const TypeInfo& dstPointeeType    = sema.typeMgr().get(dstPointeeTypeRef);

    // Ref to ref
    if (srcType.isReference())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const auto      srcPointeeTypeRef = srcType.payloadTypeRef();
        const TypeInfo& srcPointeeType    = sema.typeMgr().get(srcPointeeTypeRef);

        if (srcPointeeTypeRef == dstPointeeTypeRef)
            return Result::Continue;

        // Struct ref to interface ref
        if (srcPointeeType.isStruct() && dstPointeeType.isInterface())
        {
            const auto& fromStruct = srcPointeeType.payloadSymStruct();
            const auto& toItf      = dstPointeeType.payloadSymInterface();
            if (fromStruct.implementsInterfaceOrUsingFields(sema, toItf))
                return Result::Continue;
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
        }
    }

    // Pointer to ref
    if (srcType.isAnyPointer())
    {
        if (srcType.isNullable())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (srcType.payloadTypeRef() == dstPointeeTypeRef)
            return Result::Continue;
    }

    // Value to const ref
    if (srcType.isStruct() && dstType.isConst())
    {
        if (dstPointeeTypeRef == srcTypeRef)
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isStruct());
                const uint64_t      ptr    = reinterpret_cast<uint64_t>(srcCst.getStruct().data());
                const ConstantValue refCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptr, dstType.flags());
                castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), refCst));
            }

            return Result::Continue;
        }
    }

    // UFCS receiver: allow taking the address to bind a value to a reference.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && dstPointeeTypeRef == srcTypeRef)
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castPointerToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    const bool sameUnderlying = srcType.payloadTypeRef() == dstType.payloadTypeRef();
    const bool srcIsVoid      = srcType.payloadTypeRef() == sema.typeMgr().typeVoid();
    const bool dstIsVoid      = dstType.payloadTypeRef() == sema.typeMgr().typeVoid();
    if (sameUnderlying || srcIsVoid || dstIsVoid || castRequest.kind == CastKind::Explicit)
    {
        bool ok = false;
        if (srcType.kind() == dstType.kind())
            ok = true;
        else if (srcType.isBlockPointer() && dstType.isValuePointer())
            ok = true;
        else if (srcType.isValuePointer() && dstType.isBlockPointer() && castRequest.kind == CastKind::Explicit)
            ok = true;
        // TODO @legacy
        else if (sameUnderlying || srcIsVoid || dstIsVoid)
            ok = true;

        if (ok)
        {
            // TODO @legacy
            if (dstType.unwrap(sema.ctx(), TypeRef::invalid(), TypeExpandE::Pointer) == sema.typeMgr().typeVoid())
            {
            }
            else if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            {
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
            }

            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    // UFCS receiver: allow taking the address to get a pointer.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && dstType.payloadTypeRef() == srcTypeRef && !dstType.isNullable())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    if (srcType.isAnyPointer())
    {
        const TypeInfo& srcPointeeType = sema.typeMgr().get(srcType.payloadTypeRef());
        if (srcPointeeType.isReference() && srcPointeeType.payloadTypeRef() == dstType.payloadTypeRef())
        {
            bool ok = false;
            if (srcType.kind() == dstType.kind())
                ok = true;
            else if (srcType.isBlockPointer() && dstType.isValuePointer())
                ok = true;
            else if (srcType.isValuePointer() && dstType.isBlockPointer() && castRequest.kind == CastKind::Explicit)
                ok = true;

            if (ok)
            {
                if ((srcType.isConst() || srcPointeeType.isConst()) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

                return Result::Continue;
            }
        }

        return castPointerToPointer(sema, castRequest, srcTypeRef, dstTypeRef);
    }

    if (srcType.isTypeInfo())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (dstTypeRef == sema.typeMgr().typeConstValuePtrU8() ||
                dstTypeRef == sema.typeMgr().typeConstValuePtrVoid())
            {
                return Result::Continue;
            }
        }
    }

    if (srcTypeRef == sema.typeMgr().typeU64())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (castRequest.isConstantFolding())
            {
                if (!foldConstantIntLikeToPointer(sema, castRequest, dstTypeRef))
                    return Result::Error;
            }
            return Result::Continue;
        }
    }

    if (srcType.isArray())
    {
        const auto srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        const auto dstElemTypeRef = dstType.payloadTypeRef();

        if (castRequest.kind == CastKind::Explicit ||
            srcElemTypeRef == dstElemTypeRef ||
            dstElemTypeRef == sema.typeMgr().typeVoid())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    // TODO @legacy (for parameters of type struct, which in fact are references)
    if (srcType.isStruct())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if (srcTypeRef == dstElemTypeRef)
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToSlice(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TaskContext&    ctx     = sema.ctx();
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    // String -> const [..] u8
    if (srcType.isString())
    {
        if (dstType.isConst() && dstType.payloadTypeRef() == sema.typeMgr().typeU8())
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue&   cst  = sema.cstMgr().get(castRequest.srcConstRef);
                const std::string_view str  = cst.getString();
                const ByteSpan         span = asByteSpan(str);
                const ConstantValue    cv   = ConstantValue::makeSlice(ctx, dstType.payloadTypeRef(), span, TypeInfoFlagsE::Const);
                castRequest.outConstRef     = sema.cstMgr().addConstant(sema.ctx(), cv);
            }

            return Result::Continue;
        }
    }

    if (srcType.isArray())
    {
        const auto srcElemTypeRef = srcType.payloadArrayElemTypeRef();
        const auto dstElemTypeRef = dstType.payloadTypeRef();

        if (castRequest.kind == CastKind::Explicit || srcElemTypeRef == dstElemTypeRef)
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (srcElemTypeRef != dstElemTypeRef)
            {
                const TypeInfo& dstElemType = sema.typeMgr().get(dstElemTypeRef);
                const uint64_t  s           = dstElemType.sizeOf(ctx);
                const uint64_t  d           = srcType.sizeOf(ctx);
                const bool      match       = s == 0 || (d / s * s == d);
                if (!match)
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            }

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isArray());
                const ConstantValue sliceCst = ConstantValue::makeSlice(ctx, dstElemTypeRef, srcCst.getArray(), dstType.flags());
                castRequest.outConstRef      = sema.cstMgr().addConstant(sema.ctx(), sliceCst);
            }

            return Result::Continue;
        }
    }

    if (srcType.isAggregateArray())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const auto& srcElemTypes = srcType.payloadAggregate().types;
        for (const TypeRef srcElemTypeRef : srcElemTypes)
        {
            CastRequest elemRequest(castRequest.kind);
            elemRequest.flags        = castRequest.flags;
            elemRequest.errorNodeRef = castRequest.errorNodeRef;
            elemRequest.errorCodeRef = castRequest.errorCodeRef;
            const Result res         = castAllowed(sema, elemRequest, srcElemTypeRef, dstElemTypeRef);
            if (res != Result::Continue)
            {
                castRequest.failure = elemRequest.failure;
                return res;
            }
        }

        if (!castRequest.isConstantFolding())
            return Result::Continue;

        const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
        SWC_ASSERT(srcCst.isAggregateArray());

        const auto& srcValues = srcCst.getAggregateArray();
        SWC_ASSERT(srcValues.size() == srcElemTypes.size());

        std::vector<ConstantRef> castedValues;
        castedValues.reserve(srcValues.size());
        for (size_t i = 0; i < srcValues.size(); ++i)
        {
            CastRequest elemRequest(castRequest.kind);
            elemRequest.flags        = castRequest.flags;
            elemRequest.errorNodeRef = castRequest.errorNodeRef;
            elemRequest.errorCodeRef = castRequest.errorCodeRef;
            elemRequest.setConstantFoldingSrc(srcValues[i]);
            const Result res = castAllowed(sema, elemRequest, srcElemTypes[i], dstElemTypeRef);
            if (res != Result::Continue)
            {
                castRequest.failure = elemRequest.failure;
                return res;
            }

            ConstantRef castedRef = elemRequest.constantFoldingResult();
            if (castedRef.isInvalid())
                castedRef = srcValues[i];
            castedValues.push_back(castedRef);
        }

        SmallVector4<uint64_t> arrayDims;
        arrayDims.push_back(srcValues.size());
        const TypeRef   arrayTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(arrayDims, dstElemTypeRef));
        const TypeInfo& arrayType    = sema.typeMgr().get(arrayTypeRef);

        const uint64_t         arraySize = arrayType.sizeOf(ctx);
        std::vector<std::byte> arrayData(arraySize);
        const ByteSpanRW       arraySpan = asByteSpan(arrayData);
        ConstantLower::lowerAggregateArrayToBytes(sema, arraySpan, arrayType, castedValues);

        const ConstantValue sliceCst = ConstantValue::makeSlice(ctx, dstElemTypeRef, arraySpan, dstType.flags());
        castRequest.outConstRef      = sema.cstMgr().addConstant(sema.ctx(), sliceCst);
        return Result::Continue;
    }

    // void* -> slice (explicit only)
    if (srcType.isAnyPointer() && srcType.payloadTypeRef() == sema.typeMgr().typeVoid())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    // slice -> slice
    if (srcType.isSlice())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        if (castRequest.kind == CastKind::Explicit || srcType.payloadTypeRef() == dstType.payloadTypeRef())
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castFromTypeValue(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (dstType.isAnyTypeInfo(sema.ctx()))
    {
        if (castRequest.isConstantFolding())
        {
            const auto cst = sema.cstMgr().get(castRequest.srcConstRef);
            SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, castRequest.outConstRef, cst.getTypeValue(), castRequest.errorNodeRef));
        }

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToFromTypeInfo(const Sema& sema, const CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(castRequest);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);
    return Result::Continue;
}

Result Cast::castToFunction(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isFunction() && srcType.payloadSymFunction().sameTypeSignature(dstType.payloadSymFunction()))
        return Result::Continue;

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        srcType = typeMgr.get(srcTypeRef);
    if (srcType.isSlice())
    {
        if (castRequest.kind != CastKind::Explicit)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        if (srcType.payloadTypeRef() != typeMgr.typeU8())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    if (srcType.isArray())
    {
        if (srcType.payloadArrayElemTypeRef() == typeMgr.typeU8() && srcType.payloadArrayDims().size() == 1)
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToCString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        srcType = typeMgr.get(srcTypeRef);

    if (srcType.isBlockPointer())
    {
        if (srcType.payloadTypeRef() == sema.typeMgr().typeU8())
            return Result::Continue;
    }

    if (srcType.isArray())
    {
        if (srcType.payloadArrayElemTypeRef() == typeMgr.typeU8() && srcType.payloadArrayDims().size() == 1)
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToAny(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (!castRequest.isConstantFolding())
        return Result::Continue;

    TaskContext&       ctx        = sema.ctx();
    const TypeManager& typeMgr    = sema.typeMgr();
    ConstantRef        srcCstRef  = castRequest.srcConstRef;
    TypeRef            anyTypeRef = srcTypeRef;
    const TypeInfo*    srcType    = &typeMgr.get(anyTypeRef);

    if (srcType->isIntUnsized() || srcType->isFloatUnsized())
    {
        ConstantRef          concreteCstRef;
        const TypeInfo::Sign hintSign = srcType->isIntUnsized() ? TypeInfo::Sign::Signed : TypeInfo::Sign::Unknown;
        if (!concretizeConstant(sema, concreteCstRef, srcCstRef, hintSign))
        {
            castRequest.fail(DiagnosticId::sema_err_literal_too_big, sema.cstMgr().get(srcCstRef).typeRef(), TypeRef::invalid());
            return Result::Error;
        }

        srcCstRef  = concreteCstRef;
        anyTypeRef = sema.cstMgr().get(concreteCstRef).typeRef();
        srcType    = &typeMgr.get(anyTypeRef);
        castRequest.setConstantFoldingSrc(concreteCstRef);
    }

    if (srcType->isChar())
    {
        const ConstantValue runeCst = ConstantValue::makeRune(ctx, sema.cstMgr().get(srcCstRef).getChar());
        srcCstRef                   = sema.cstMgr().addConstant(ctx, runeCst);
        anyTypeRef                  = typeMgr.typeRune();
        srcType                     = &typeMgr.get(anyTypeRef);
        castRequest.setConstantFoldingSrc(srcCstRef);
    }

    const ConstantValue& srcCst = sema.cstMgr().get(srcCstRef);

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, anyTypeRef, castRequest.errorNodeRef));
    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());
    uint32_t  shardIndex     = 0;
    const Ref typeInfoOffset = sema.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    SWC_ASSERT(typeInfoOffset != INVALID_REF);
    if (typeInfoOffset == INVALID_REF)
        return Result::Error;

    DataSegment& segment            = sema.cstMgr().shardDataSegment(shardIndex);
    const auto [anyOffset, storage] = segment.reserveBytes(sizeof(Runtime::Any), alignof(Runtime::Any), true);
    auto* const runtimeAny          = reinterpret_cast<Runtime::Any*>(storage);
    runtimeAny->type                = segment.ptr<Runtime::TypeInfo>(typeInfoOffset);
    segment.addRelocation(anyOffset + offsetof(Runtime::Any, type), typeInfoOffset);

    if (!srcCst.isNull())
    {
        const uint64_t valueSize = srcType->sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());

        if (valueSize)
        {
            std::vector valueBytes(valueSize, std::byte{0});
            ConstantLower::lowerToBytes(sema, valueBytes, srcCstRef, anyTypeRef);

            uint32_t valueOffset = INVALID_REF;
            SWC_RESULT(ConstantLower::materializeStaticPayload(valueOffset, sema, segment, anyTypeRef, ByteSpan{valueBytes.data(), valueBytes.size()}));
            runtimeAny->value = segment.ptr<std::byte>(valueOffset);
            segment.addRelocation(anyOffset + offsetof(Runtime::Any, value), valueOffset);
        }
    }

    const ConstantValue anyCst = ConstantValue::makeStructBorrowed(ctx, dstTypeRef, ByteSpan{storage, sizeof(Runtime::Any)});
    castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(ctx, anyCst));
    return Result::Continue;
}

Result Cast::castToVariadic(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const auto&        dstType = typeMgr.get(dstTypeRef);

    if (dstType.isVariadic())
        return Result::Continue;

    if (dstType.isTypedVariadic())
        return castAllowed(sema, castRequest, srcTypeRef, dstType.payloadTypeRef());

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToInterface(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isStruct())
    {
        const SymbolStruct& fromStruct = srcType.payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&srcType, castRequest.errorNodeRef));
        const SymbolInterface& toItf = dstType.payloadSymInterface();
        if (fromStruct.implementsInterfaceOrUsingFields(sema, toItf))
            return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
}

Result Cast::castFromAny(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    if (!castRequest.isConstantFolding())
        return Result::Continue;

    TaskContext&         ctx    = sema.ctx();
    const ConstantValue& anyCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
    if (!anyCst.isStruct())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const ByteSpan anyBytes = anyCst.getStruct();
    if (anyBytes.size() != sizeof(Runtime::Any))
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    Runtime::Any runtimeAny{};
    std::memcpy(&runtimeAny, anyBytes.data(), sizeof(runtimeAny));

    const TypeRef valueTypeRef = sema.typeGen().getBackTypeRef(runtimeAny.type);
    if (!valueTypeRef.isValid())
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    ConstantRef valueCstRef = ConstantRef::invalid();
    if (!runtimeAny.value)
    {
        valueCstRef = sema.cstMgr().cstNull();
    }
    else
    {
        const TypeInfo& valueType = sema.typeMgr().get(valueTypeRef);

        if (valueType.isEnum())
        {
            const TypeRef       underlyingTypeRef = valueType.payloadSymEnum().underlyingTypeRef();
            const ConstantValue underlyingCst     = ConstantValue::make(ctx, runtimeAny.value, underlyingTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!underlyingCst.isValid())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

            const ConstantRef   underlyingCstRef = sema.cstMgr().addConstant(ctx, underlyingCst);
            const ConstantValue enumCst          = ConstantValue::makeEnumValue(ctx, underlyingCstRef, valueTypeRef);
            valueCstRef                          = sema.cstMgr().addConstant(ctx, enumCst);
        }
        else if (valueType.isAnyTypeInfo(ctx))
        {
            const uint64_t ptrValue = reinterpret_cast<uint64_t>(runtimeAny.value);
            ConstantValue  typeCst  = ConstantValue::makeValuePointer(ctx, sema.typeMgr().structTypeInfo(), ptrValue, TypeInfoFlagsE::Const);
            typeCst.setTypeRef(valueTypeRef);
            valueCstRef = sema.cstMgr().addConstant(ctx, typeCst);
        }
        else
        {
            const ConstantValue valueCst = ConstantValue::make(ctx, runtimeAny.value, valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!valueCst.isValid())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
            valueCstRef = sema.cstMgr().addConstant(ctx, valueCst);
        }
    }

    CastRequest castFromAnyRequest(CastKind::Explicit);
    castFromAnyRequest.flags        = castRequest.flags;
    castFromAnyRequest.errorNodeRef = castRequest.errorNodeRef;
    castFromAnyRequest.errorCodeRef = castRequest.errorCodeRef;
    castFromAnyRequest.setConstantFoldingSrc(valueCstRef);

    const Result result = castAllowed(sema, castFromAnyRequest, valueTypeRef, dstTypeRef);
    if (result != Result::Continue)
    {
        if (result == Result::Error)
            castRequest.failure = castFromAnyRequest.failure;
        return result;
    }

    castRequest.setConstantFoldingResult(castFromAnyRequest.constantFoldingResult());
    return Result::Continue;
}

Result Cast::castAllowed(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (srcTypeRef == dstTypeRef)
        return castIdentity(sema, castRequest, srcTypeRef, dstTypeRef);

    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    if (srcType.isAlias() || dstType.isAlias())
    {
        const bool allowAliasConditionToBool = castRequest.kind == CastKind::Condition && dstType.isBool();
        if (castRequest.kind != CastKind::Explicit && !allowAliasConditionToBool)
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    auto res = Result::Error;
    if (srcType.isAlias())
        res = castAllowed(sema, castRequest, srcType.payloadSymAlias().underlyingTypeRef(), dstTypeRef);
    else if (srcType.isAny())
        res = castFromAny(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAlias())
        res = castAllowed(sema, castRequest, srcTypeRef, dstType.payloadSymAlias().underlyingTypeRef());
    else if (castRequest.flags.has(CastFlagsE::BitCast))
        res = castBit(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (shouldRouteEnumViaUnderlying(castRequest, srcType, dstType))
        res = castFromEnum(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isNull())
        res = castFromNull(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isUndefined())
        res = castFromUndefined(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isBool())
        res = castToBool(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isIntLike())
        res = castToIntLike(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isFloat())
        res = castToFloat(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isTypeValue())
        res = castFromTypeValue(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (srcType.isAnyTypeInfo(sema.ctx()) && dstType.isAnyTypeInfo(sema.ctx()))
        res = castToFromTypeInfo(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isFunction())
        res = castToFunction(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isArray())
        res = castToArray(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isSlice())
        res = castToSlice(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyPointer())
        res = castToPointer(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAny())
        res = castToAny(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isReference())
        res = castToReference(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isInterface())
        res = castToInterface(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isAnyVariadic())
        res = castToVariadic(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isString())
        res = castToString(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isCString())
        res = castToCString(sema, castRequest, srcTypeRef, dstTypeRef);
    else if (dstType.isStruct())
        res = castToStruct(sema, castRequest, srcTypeRef, dstTypeRef);
    else
    {
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
    }

    if (res == Result::Continue && castRequest.isConstantFolding())
    {
        ConstantValue resCst = sema.cstMgr().get(castRequest.outConstRef);
        if (resCst.typeRef() != dstTypeRef)
        {
            resCst.setTypeRef(dstTypeRef);
            castRequest.outConstRef = sema.cstMgr().addConstant(sema.ctx(), resCst);
        }
    }

    return res;
}

TypeRef Cast::castAllowedBothWays(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castAllowed(sema, castRequest, srcTypeRef, dstTypeRef) == Result::Continue)
        return dstTypeRef;
    if (castAllowed(sema, castRequest, dstTypeRef, srcTypeRef) == Result::Continue)
        return srcTypeRef;
    return TypeRef::invalid();
}

TypeRef Cast::castAllowedBothWays(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastKind castKind)
{
    CastRequest castRequest(castKind);
    return castAllowedBothWays(sema, castRequest, srcTypeRef, dstTypeRef);
}

Result Cast::cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags)
{
    CastKind  effectiveKind  = castKind;
    CastFlags effectiveFlags = castFlags;

    // `cast()` is an explicit user request to allow explicit casts later when the destination type becomes known.
    // Therefore, when we are about to apply a contextual cast on an `AutoCastExpr`, force the cast to be explicit
    // and apply its modifiers.
    SWC_ASSERT(view.node() != nullptr);
    if (view.node()->is(AstNodeId::AutoCastExpr))
    {
        const auto& autoCast = view.node()->cast<AstAutoCastExpr>();
        effectiveKind        = CastKind::Explicit;
        if (autoCast.modifierFlags.has(AstModifierFlagsE::Bit))
            effectiveFlags.add(CastFlagsE::BitCast);
        if (autoCast.modifierFlags.has(AstModifierFlagsE::UnConst))
            effectiveFlags.add(CastFlagsE::UnConst);
    }

    if (view.cstRef().isValid() && sema.isFoldedTypedConst(view.nodeRef()))
        effectiveFlags.add(CastFlagsE::FoldedTypedConst);

    if (view.typeRef() == dstTypeRef && effectiveFlags == CastFlagsE::Zero)
        return Result::Continue;

    CastRequest castRequest(effectiveKind);
    castRequest.flags        = effectiveFlags;
    castRequest.errorNodeRef = view.nodeRef();
    castRequest.setConstantFoldingSrc(view.cstRef());

    const Result result = castAllowed(sema, castRequest, view.typeRef(), dstTypeRef);
    if (result == Result::Pause)
        return result;

    // Success !
    if (result == Result::Continue)
    {
        if (castRequest.constantFoldingResult().isInvalid())
        {
            if (castFlags.has(CastFlagsE::FromExplicitNode))
                sema.setType(view.nodeRef(), dstTypeRef);
            else
            {
                const TypeRef     srcTypeRef = view.typeRef();
                const ConstantRef srcCstRef  = view.cstRef();
                const AstNodeRef  srcNodeRef = view.nodeRef();
                SWC_RESULT(retargetLiteralRuntimeStorageIfNeeded(sema, srcNodeRef, srcTypeRef, dstTypeRef));
                view.nodeRef() = createCast(sema, dstTypeRef, srcNodeRef);
                SWC_RESULT(attachCastRuntimeStorageIfNeeded(sema, view.nodeRef(), srcTypeRef, dstTypeRef, srcCstRef));
            }
        }
        else
        {
            sema.setType(view.nodeRef(), dstTypeRef);
            sema.setConstant(view.nodeRef(), castRequest.constantFoldingResult());
        }

        view.recompute(sema);
        return Result::Continue;
    }

    if (effectiveKind != CastKind::Explicit)
    {
        CastRequest explicitCtx(CastKind::Explicit);
        explicitCtx.errorNodeRef = view.nodeRef();
        if (castAllowed(sema, explicitCtx, view.typeRef(), dstTypeRef) == Result::Continue)
            castRequest.failure.noteId = DiagnosticId::sema_note_cast_explicit;
    }

    return emitCastFailure(sema, castRequest.failure);
}

Result Cast::castIfNeeded(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags)
{
    if (view.typeRef() == dstTypeRef)
        return Result::Continue;

    return cast(sema, view, dstTypeRef, castKind, castFlags);
}

Result Cast::castPromote(Sema& sema, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView, CastKind castKind)
{
    if (!nodeLeftView.type() || !nodeRightView.type())
        return Result::Continue;

    if (!nodeLeftView.type()->isScalarNumeric() || !nodeRightView.type()->isScalarNumeric())
        return Result::Continue;

    const TypeRef promotedTypeRef = sema.typeMgr().promote(nodeLeftView.typeRef(), nodeRightView.typeRef(), false);
    SWC_RESULT(castIfNeeded(sema, nodeLeftView, promotedTypeRef, castKind));
    SWC_RESULT(castIfNeeded(sema, nodeRightView, promotedTypeRef, castKind));
    return Result::Continue;
}

SWC_END_NAMESPACE();
