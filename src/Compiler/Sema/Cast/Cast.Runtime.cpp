#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t sliceCountFromArrayCast(TaskContext& ctx, const TypeInfo& srcArrayType, const TypeInfo& dstElementType)
    {
        const uint64_t dstElementSize = dstElementType.sizeOf(ctx);
        if (dstElementSize)
            return srcArrayType.sizeOf(ctx) / dstElementSize;

        uint64_t totalCount = 1;
        for (const uint64_t dim : srcArrayType.payloadArrayDims())
            totalCount *= dim;
        return totalCount;
    }

    uint64_t pointerValueFromPointerLikeConstant(const ConstantValue& cst)
    {
        if (cst.isBlockPointer())
            return cst.getBlockPointer();
        if (cst.isValuePointer())
            return cst.getValuePointer();
        if (cst.isNull())
            return 0;

        SWC_ASSERT(false);
        return 0;
    }

    std::string_view stringViewFromCStringConstant(const ConstantValue& cst)
    {
        const uint64_t ptrValue = pointerValueFromPointerLikeConstant(cst);
        if (!ptrValue)
            return {};

        const auto* ptr = reinterpret_cast<const char*>(ptrValue);
        return {ptr, std::strlen(ptr)};
    }

    ByteSpan byteSpanFromCStringView(std::string_view view)
    {
        if (view.empty())
            return {};
        return {reinterpret_cast<const std::byte*>(view.data()), view.size()};
    }

    void setCStringPointerConstant(Sema& sema, CastRequest& castRequest, TypeRef dstTypeRef, const TypeInfo& dstType, uint64_t ptrValue)
    {
        ConstantValue ptrCst = ConstantValue::makeBlockPointer(sema.ctx(), sema.typeMgr().typeU8(), ptrValue, dstType.flags());
        ptrCst.setTypeRef(dstTypeRef);
        castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), ptrCst));
    }

    void setAnyPointerConstant(Sema& sema, CastRequest& castRequest, TypeRef dstPointeeTypeRef, const TypeInfo& dstType, uint64_t ptrValue)
    {
        SWC_ASSERT(dstType.isAnyPointer());

        ConstantValue ptrCst;
        if (dstType.isBlockPointer())
            ptrCst = ConstantValue::makeBlockPointer(sema.ctx(), dstPointeeTypeRef, ptrValue, dstType.flags());
        else
            ptrCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptrValue, dstType.flags());

        castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), ptrCst));
    }

    ConstantRef addValuePointerConstant(Sema& sema, TypeRef dstPointeeTypeRef, TypeInfoFlags dstFlags, uint64_t ptrValue)
    {
        const ConstantValue ptrCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptrValue, dstFlags);
        return sema.cstMgr().addConstant(sema.ctx(), ptrCst);
    }

    CastRequest makeNestedCastRequest(const CastRequest& parent)
    {
        CastRequest nested(parent.kind);
        nested.flags        = parent.flags;
        nested.errorNodeRef = parent.errorNodeRef;
        nested.errorCodeRef = parent.errorCodeRef;
        return nested;
    }

    TypeRef unwrapAliasEnumTypeRef(const TypeManager& typeMgr, const TaskContext& ctx, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = typeMgr.get(typeRef).unwrapAliasEnum(ctx, typeRef);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    Result makeTypeInfoWithoutBlocking(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef)
    {
        const Result result = sema.cstMgr().makeTypeInfo(sema, outRef, typeRef, ownerNodeRef, ConstantManager::TypeInfoLockMode::TryLock);
        if (result != Result::Pause)
            return result;

        if (sema.ctx().state().hasPauseReason())
            return Result::Pause;

        // Type-info cache contention is transient work sharing, not a semantic dependency.
        // Yield here so another worker can keep progressing until the shard owner publishes.
        return sema.waitTypeInfoGeneration(ownerNodeRef);
    }

    Result constantFoldPointerLikeFromValue(Sema& sema, ConstantRef srcCstRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef& outCstRef)
    {
        const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
        SWC_ASSERT(dstType.isAnyPointer() || dstType.isReference() || dstType.isMoveReference());

        uint64_t       ptr       = 0;
        const uint64_t valueSize = srcType.sizeOf(sema.ctx());
        if (valueSize)
        {
            std::vector valueBytes(valueSize, std::byte{0});
            SWC_RESULT(ConstantLower::lowerToBytes(sema, asByteSpan(valueBytes), srcCstRef, srcTypeRef));
            const std::string_view rawValueData = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(valueBytes)));
            ptr                                 = reinterpret_cast<uint64_t>(rawValueData.data());
        }

        outCstRef = addValuePointerConstant(sema, dstType.payloadTypeRef(), dstType.flags(), ptr);
        return Result::Continue;
    }

    bool usingPathHasPointerStep(const SmallVector<SymbolStructUsingPathStep>& usingPath)
    {
        for (const auto& step : usingPath)
        {
            if (step.isPointer)
                return true;
        }

        return false;
    }

    Result resolveUsingStructCastPath(Sema& sema, const CastRequest& castRequest, TypeRef srcStructTypeRef, TypeRef dstStructTypeRef, SmallVector<SymbolStructUsingPathStep>& outSteps, bool& outFound)
    {
        outFound = false;
        outSteps.clear();

        srcStructTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcStructTypeRef);
        dstStructTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstStructTypeRef);
        if (!srcStructTypeRef.isValid() || !dstStructTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& srcStructType = sema.typeMgr().get(srcStructTypeRef);
        const TypeInfo& dstStructType = sema.typeMgr().get(dstStructTypeRef);
        if (!srcStructType.isStruct() || !dstStructType.isStruct())
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(&srcStructType, castRequest.errorNodeRef));
        SWC_RESULT(sema.waitSemaCompleted(&dstStructType, castRequest.errorNodeRef));

        outFound = srcStructType.payloadSymStruct().resolveUsingFieldPath(sema.ctx(), dstStructType.payloadSymStruct(), outSteps);
        return Result::Continue;
    }

    Result resolveUsingStructCastPathWithoutPointerStep(Sema& sema, const CastRequest& castRequest, TypeRef srcStructTypeRef, TypeRef dstStructTypeRef, bool& outFound)
    {
        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   hasUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPath(sema, castRequest, srcStructTypeRef, dstStructTypeRef, usingPath, hasUsingPath));
        outFound = hasUsingPath && !usingPathHasPointerStep(usingPath);
        return Result::Continue;
    }

    bool pointerKindsCompatible(const TypeInfo& srcType, const TypeInfo& dstType, const CastKind castKind)
    {
        if (srcType.kind() == dstType.kind())
            return true;
        if (srcType.isBlockPointer() && dstType.isValuePointer())
            return true;
        if (srcType.isValuePointer() && dstType.isBlockPointer() && castKind == CastKind::Explicit)
            return true;
        return false;
    }

    bool pointerPayloadShortcutMatches(const TypeManager& typeMgr, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        return srcType.payloadTypeRef() == dstType.payloadTypeRef() ||
               srcType.payloadTypeRef() == typeMgr.typeVoid() ||
               dstType.payloadTypeRef() == typeMgr.typeVoid();
    }

    bool pointerKindsCompatibleWithLegacyPayloadShortcut(const TypeManager& typeMgr, const TypeInfo& srcType, const TypeInfo& dstType, const CastKind castKind)
    {
        if (pointerKindsCompatible(srcType, dstType, castKind))
            return true;

        // Keep the historical same-payload / void relaxation localized instead of duplicating it at each cast site.
        return pointerPayloadShortcutMatches(typeMgr, srcType, dstType);
    }

    bool allowsLegacyStructByValuePointerCast(const TypeManager& typeMgr, TypeRef srcStructTypeRef, TypeRef dstPointeeTypeRef)
    {
        // Preserve the current behavior while struct parameters still lower like implicit references.
        return srcStructTypeRef == dstPointeeTypeRef || dstPointeeTypeRef == typeMgr.typeVoid();
    }

    bool pointerPayloadsCompatible(Sema& sema, const CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return true;

        srcTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), srcTypeRef);
        dstTypeRef = unwrapAliasEnumTypeRef(sema.typeMgr(), sema.ctx(), dstTypeRef);
        if (srcTypeRef == dstTypeRef)
            return true;
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return false;

        const TypeManager& typeMgr = sema.typeMgr();
        const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
        const TypeInfo&    dstType = typeMgr.get(dstTypeRef);
        if (!srcType.isAnyPointer() || !dstType.isAnyPointer())
            return false;
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return false;

        const bool payloadShortcut = pointerPayloadShortcutMatches(typeMgr, srcType, dstType);
        if (!pointerKindsCompatibleWithLegacyPayloadShortcut(typeMgr, srcType, dstType, castRequest.kind))
            return false;

        if (payloadShortcut)
            return true;
        return pointerPayloadsCompatible(sema, castRequest, srcType.payloadTypeRef(), dstType.payloadTypeRef());
    }

    bool sameFunctionTypeRecursive(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef);

    bool sameFunctionSignatureRecursive(Sema& sema, const SymbolFunction& leftFunc, const SymbolFunction& rightFunc, const bool ignoreTopLevelClosure)
    {
        if (&leftFunc == &rightFunc)
            return true;

        if (!sameFunctionTypeRecursive(sema, leftFunc.returnTypeRef(), rightFunc.returnTypeRef()))
            return false;
        if (leftFunc.callConvKind() != rightFunc.callConvKind())
            return false;
        if (!ignoreTopLevelClosure && leftFunc.isClosure() != rightFunc.isClosure())
            return false;
        if (leftFunc.isMethod() != rightFunc.isMethod())
            return false;
        if (leftFunc.isThrowable() != rightFunc.isThrowable())
            return false;
        if (leftFunc.isConst() != rightFunc.isConst())
            return false;
        if (leftFunc.hasVariadicParam() != rightFunc.hasVariadicParam())
            return false;

        const auto& leftParams  = leftFunc.parameters();
        const auto& rightParams = rightFunc.parameters();
        if (leftParams.size() != rightParams.size())
            return false;

        for (uint32_t i = 0; i < leftParams.size(); ++i)
        {
            SWC_ASSERT(leftParams[i] != nullptr);
            SWC_ASSERT(rightParams[i] != nullptr);
            if (!sameFunctionTypeRecursive(sema, leftParams[i]->typeRef(), rightParams[i]->typeRef()))
                return false;
        }

        return true;
    }

    bool sameFunctionTypeRecursive(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (leftTypeRef == rightTypeRef)
            return true;
        if (!leftTypeRef.isValid() || !rightTypeRef.isValid())
            return false;

        const TypeInfo& leftType  = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = sema.typeMgr().get(rightTypeRef);
        if (!leftType.isFunction() || !rightType.isFunction())
            return false;

        return sameFunctionSignatureRecursive(sema, leftType.payloadSymFunction(), rightType.payloadSymFunction(), false);
    }
}

Result Cast::castPointerToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    const bool payloadShortcut = pointerPayloadShortcutMatches(typeMgr, srcType, dstType);
    if (payloadShortcut || castRequest.kind == CastKind::Explicit)
    {
        if (pointerKindsCompatibleWithLegacyPayloadShortcut(typeMgr, srcType, dstType, castRequest.kind))
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    if (pointerKindsCompatible(srcType, dstType, castRequest.kind))
    {
        if (pointerPayloadsCompatible(sema, castRequest, srcType.payloadTypeRef(), dstType.payloadTypeRef()))
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }

        bool hasCompatibleUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcType.payloadTypeRef(), dstType.payloadTypeRef(), hasCompatibleUsingPath));
        if (hasCompatibleUsingPath)
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeManager& typeMgr = sema.typeMgr();
    const TypeInfo&    srcType = typeMgr.get(srcTypeRef);
    const TypeInfo&    dstType = typeMgr.get(dstTypeRef);

    // UFCS receiver: allow taking the address to get a pointer.
    // Whether the value is actually addressable (lvalue) is validated later by `Cast::cast`.
    if (castRequest.flags.has(CastFlagsE::UfcsArgument) && dstType.payloadTypeRef() == srcTypeRef && !dstType.isNullable())
    {
        const bool sourceIsConst = srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource);
        if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        return Result::Continue;
    }

    if (srcType.isFunction() &&
        castRequest.kind == CastKind::Explicit &&
        dstType.payloadTypeRef() == typeMgr.typeVoid())
    {
        return Result::Continue;
    }

    if (srcType.isReference())
    {
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const TypeRef dstPointeeTypeRef = dstType.payloadTypeRef();
        if (srcType.payloadTypeRef() == dstPointeeTypeRef || dstPointeeTypeRef == typeMgr.typeVoid())
            return Result::Continue;

        bool hasCompatibleUsingPath = false;
        SWC_RESULT(resolveUsingStructCastPathWithoutPointerStep(sema, castRequest, srcType.payloadTypeRef(), dstPointeeTypeRef, hasCompatibleUsingPath));
        if (hasCompatibleUsingPath)
            return Result::Continue;
    }

    if (srcType.isAnyPointer())
    {
        const TypeInfo& srcPointeeType = typeMgr.get(srcType.payloadTypeRef());
        if (srcPointeeType.isArray() && srcPointeeType.payloadArrayElemTypeRef() == dstType.payloadTypeRef())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            return Result::Continue;
        }

        if (srcPointeeType.isReference() && srcPointeeType.payloadTypeRef() == dstType.payloadTypeRef())
        {
            if (pointerKindsCompatible(srcType, dstType, castRequest.kind))
            {
                if ((srcType.isConst() || srcPointeeType.isConst()) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

                return Result::Continue;
            }
        }

        return castPointerToPointer(sema, castRequest, srcTypeRef, dstTypeRef);
    }

    if (srcType.isString())
    {
        const TypeRef dstPointeeTypeRef = dstType.payloadTypeRef();
        if (castRequest.kind == CastKind::Explicit &&
            dstType.isConst() &&
            (dstPointeeTypeRef == typeMgr.typeU8() || dstPointeeTypeRef == typeMgr.typeVoid()))
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isString());
                const uint64_t ptrValue = reinterpret_cast<uint64_t>(srcCst.getString().data());
                setAnyPointerConstant(sema, castRequest, dstPointeeTypeRef, dstType, ptrValue);
            }

            return Result::Continue;
        }
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
            const bool sourceIsConst = srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource);
            if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isArray());
                const uint64_t ptrValue = reinterpret_cast<uint64_t>(srcCst.getArray().data());
                setAnyPointerConstant(sema, castRequest, dstElemTypeRef, dstType, ptrValue);
            }

            return Result::Continue;
        }
    }

    // Preserve the current struct-by-value pointer cast behavior until struct parameters stop lowering like references.
    if (srcType.isStruct())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if (allowsLegacyStructByValuePointerCast(typeMgr, srcTypeRef, dstElemTypeRef))
        {
            const bool sourceIsConst = srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource);
            if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isStruct());
                const uint64_t ptrValue = reinterpret_cast<uint64_t>(srcCst.getStruct().data());
                setAnyPointerConstant(sema, castRequest, dstElemTypeRef, dstType, ptrValue);
            }

            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToSlice(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    TaskContext&    ctx     = sema.ctx();
    TypeManager&    typeMgr = sema.typeMgr();
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    const TypeInfo& dstType = typeMgr.get(dstTypeRef);

    // String -> const [..] u8
    if (srcType.isString())
    {
        if (dstType.isConst() && dstType.payloadTypeRef() == typeMgr.typeU8())
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
            const bool sourceIsConst = srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource);
            if (sourceIsConst && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
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
                const TypeInfo&     dstElemType = sema.typeMgr().get(dstElemTypeRef);
                const uint64_t      sliceCount  = sliceCountFromArrayCast(ctx, srcType, dstElemType);
                const ConstantValue sliceCst    = ConstantValue::makeSliceCounted(ctx, dstElemTypeRef, srcCst.getArray(), sliceCount, dstType.flags());
                castRequest.outConstRef         = sema.cstMgr().addConstant(sema.ctx(), sliceCst);
            }

            return Result::Continue;
        }
    }

    // cstring -> const [..] u8
    if (srcType.isCString())
    {
        if (castRequest.kind == CastKind::Explicit && dstType.payloadTypeRef() == typeMgr.typeU8())
        {
            if (!dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
            {
                const ConstantValue&   srcCst   = sema.cstMgr().get(castRequest.constantFoldingSrc());
                const std::string_view view     = stringViewFromCStringConstant(srcCst);
                const ConstantValue    sliceCst = ConstantValue::makeSliceBorrowedCounted(ctx, dstType.payloadTypeRef(), byteSpanFromCStringView(view), view.size(), dstType.flags());
                castRequest.outConstRef         = sema.cstMgr().addConstant(ctx, sliceCst);
            }

            return Result::Continue;
        }
    }

    if (srcType.isAggregateArray())
    {
        const auto dstElemTypeRef = dstType.payloadTypeRef();
        if ((srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource)) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

        const auto& srcElemTypes = srcType.payloadAggregate().types;
        for (const TypeRef srcElemTypeRef : srcElemTypes)
        {
            CastRequest  elemRequest = makeNestedCastRequest(castRequest);
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
            CastRequest elemRequest = makeNestedCastRequest(castRequest);
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
        SWC_RESULT(ConstantLower::lowerAggregateArrayToBytes(sema, arraySpan, arrayType, castedValues));

        const ConstantValue sliceCst = ConstantValue::makeSliceCounted(ctx, dstElemTypeRef, arraySpan, srcValues.size(), dstType.flags());
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
            SWC_RESULT(makeTypeInfoWithoutBlocking(sema, castRequest.outConstRef, cst.getTypeValue(), castRequest.errorNodeRef));
        }

        return Result::Continue;
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);
}

Result Cast::castToFromTypeInfo(const Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    SWC_UNUSED(sema);
    SWC_UNUSED(srcTypeRef);
    SWC_UNUSED(dstTypeRef);

    if (castRequest.isConstantFolding())
        castRequest.outConstRef = castRequest.srcConstRef;

    return Result::Continue;
}

Result Cast::castToFunction(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

    if (srcType.isFunction())
    {
        const SymbolFunction& srcFunc = srcType.payloadSymFunction();
        const SymbolFunction& dstFunc = dstType.payloadSymFunction();
        if (sameFunctionSignatureRecursive(sema, srcFunc, dstFunc, false))
            return Result::Continue;
        if (!srcFunc.isClosure() && dstFunc.isClosure() && sameFunctionSignatureRecursive(sema, srcFunc, dstFunc, true))
            return Result::Continue;
    }

    if (castRequest.kind == CastKind::Explicit &&
        srcType.isAnyPointer() &&
        srcType.payloadTypeRef() == sema.typeMgr().typeVoid() &&
        !dstType.isLambdaClosure())
    {
        if (castRequest.isConstantFolding())
        {
            const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
            ConstantValue        fnCst  = ConstantValue::makeValuePointer(sema.ctx(), sema.typeMgr().typeVoid(), pointerValueFromPointerLikeConstant(srcCst), TypeInfoFlagsE::Const);
            fnCst.setTypeRef(dstTypeRef);
            castRequest.setConstantFoldingResult(sema.cstMgr().addConstant(sema.ctx(), fnCst));
        }

        return Result::Continue;
    }

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

    if (srcType.isCString())
    {
        if (castRequest.kind == CastKind::Explicit)
        {
            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                const ConstantValue  strCst = ConstantValue::makeString(sema.ctx(), stringViewFromCStringConstant(srcCst));
                castRequest.outConstRef     = sema.cstMgr().addConstant(sema.ctx(), strCst);
            }

            return Result::Continue;
        }
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
    const auto&        dstType = typeMgr.get(dstTypeRef);

    if (srcType.isAnyPointer())
    {
        if (srcType.payloadTypeRef() == sema.typeMgr().typeU8())
        {
            if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                setCStringPointerConstant(sema, castRequest, dstTypeRef, dstType, pointerValueFromPointerLikeConstant(srcCst));
            }

            return Result::Continue;
        }
    }

    if (srcType.isArray())
    {
        if (srcType.payloadArrayElemTypeRef() == typeMgr.typeU8() && srcType.payloadArrayDims().size() == 1)
        {
            if ((srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource)) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
            {
                const ConstantValue& srcCst = sema.cstMgr().get(castRequest.constantFoldingSrc());
                SWC_ASSERT(srcCst.isArray());
                const uint64_t ptrValue = reinterpret_cast<uint64_t>(srcCst.getArray().data());
                setCStringPointerConstant(sema, castRequest, dstTypeRef, dstType, ptrValue);
            }

            return Result::Continue;
        }
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

    if (SemaHelpers::isTypeLikeTypeRef(ctx, anyTypeRef))
    {
        const AstNodeRef ownerNodeRef = castRequest.errorNodeRef.isValid() ? castRequest.errorNodeRef : sema.ctx().state().nodeRef;
        SWC_RESULT(SemaHelpers::normalizeTypeInfoConstantRef(sema, srcCstRef, ownerNodeRef));
        anyTypeRef = sema.cstMgr().get(srcCstRef).typeRef();
        srcType    = &typeMgr.get(anyTypeRef);
        castRequest.setConstantFoldingSrc(srcCstRef);
    }

    const ConstantValue& srcCst = sema.cstMgr().get(srcCstRef);
    if (srcCst.isNull())
    {
        const ConstantRef nullAnyCstRef = sema.cstMgr().addZeroPayloadConstant(ctx, dstTypeRef);
        SWC_ASSERT(nullAnyCstRef.isValid());
        castRequest.setConstantFoldingResult(nullAnyCstRef);
        return Result::Continue;
    }

    const TypeRef boxedAnyTypeRef = SemaHelpers::preciseAnyBoxedValueTypeRef(sema, anyTypeRef, srcCstRef, castRequest.errorNodeRef);
    SWC_ASSERT(boxedAnyTypeRef.isValid());
    const bool boxedAsTypeInfo = sema.typeMgr().get(boxedAnyTypeRef).isTypeInfo();

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(makeTypeInfoWithoutBlocking(sema, typeInfoCstRef, boxedAnyTypeRef, castRequest.errorNodeRef));
    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());
    DataSegmentRef typeInfoRef;
    const bool     hasTypeInfoRef = sema.cstMgr().resolveConstantDataSegmentRef(typeInfoRef, typeInfoCstRef, reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    SWC_ASSERT(hasTypeInfoRef);
    if (!hasTypeInfoRef)
        return Result::Error;

    const uint64_t boxedValueSize   = sema.typeMgr().get(boxedAnyTypeRef).sizeOf(ctx);
    const bool     needsEmptySlot   = boxedValueSize == 0;
    DataSegment&   segment          = sema.cstMgr().shardDataSegment(typeInfoRef.shardIndex);
    const auto [anyOffset, storage] = segment.reserveBytes(sizeof(Runtime::Any) + (needsEmptySlot ? 1u : 0u), alignof(Runtime::Any), true);
    auto* runtimeAny                = reinterpret_cast<Runtime::Any*>(storage);
    runtimeAny->type                = segment.ptr<Runtime::TypeInfo>(typeInfoRef.offset);
    segment.addRelocation(anyOffset + offsetof(Runtime::Any, type), typeInfoRef.offset);

    if (!srcCst.isNull())
    {
        const uint64_t valueSize = srcType->sizeOf(ctx);
        SWC_ASSERT(valueSize <= std::numeric_limits<uint32_t>::max());
        SWC_ASSERT(boxedValueSize <= std::numeric_limits<uint32_t>::max());

        if (boxedValueSize)
        {
            uint32_t valueOffset = INVALID_REF;
            if (boxedAsTypeInfo)
            {
                SWC_ASSERT(srcCst.isValuePointer());
                const uint64_t ptrValue = srcCst.getValuePointer();
                const ByteSpan ptrBytes{reinterpret_cast<const std::byte*>(&ptrValue), sizeof(ptrValue)};
                SWC_RESULT(ConstantLower::materializeStaticPayload(valueOffset, sema, segment, boxedAnyTypeRef, ptrBytes));
            }
            else
            {
                std::vector valueBytes(boxedValueSize, std::byte{0});
                SWC_RESULT(ConstantLower::lowerToBytes(sema, valueBytes, srcCstRef, boxedAnyTypeRef));
                SWC_RESULT(ConstantLower::materializeStaticPayload(valueOffset, sema, segment, boxedAnyTypeRef, ByteSpan{valueBytes.data(), valueBytes.size()}));
            }

            runtimeAny->value = segment.ptr<std::byte>(valueOffset);
            segment.addRelocation(anyOffset + offsetof(Runtime::Any, value), valueOffset);
        }
        else
        {
            const uint32_t valueOffset = anyOffset + sizeof(Runtime::Any);
            runtimeAny->value          = segment.ptr<std::byte>(valueOffset);
            segment.addRelocation(anyOffset + offsetof(Runtime::Any, value), valueOffset);
        }
    }

    ConstantValue anyCst = ConstantValue::makeStructBorrowed(ctx, dstTypeRef, ByteSpan{storage, sizeof(Runtime::Any)});
    anyCst.setDataSegmentRef({.shardIndex = typeInfoRef.shardIndex, .offset = anyOffset});
    castRequest.setConstantFoldingResult(sema.cstMgr().addMaterializedPayloadConstant(anyCst));
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

    if (srcType.isInterface())
    {
        if (&srcType.payloadSymInterface() != &dstType.payloadSymInterface())
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
        if (srcType.isConst() && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
            return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);
        return Result::Continue;
    }

    if (srcType.isStruct())
    {
        const SymbolStruct& fromStruct = srcType.payloadSymStruct();
        SWC_RESULT(sema.waitSemaCompleted(&srcType, castRequest.errorNodeRef));
        const SymbolInterface& toItf = dstType.payloadSymInterface();
        if (fromStruct.implementsInterfaceOrUsingFields(sema, toItf))
        {
            if ((srcType.isConst() || castRequest.flags.has(CastFlagsE::ConstSource)) && !dstType.isConst() && !castRequest.flags.has(CastFlagsE::UnConst))
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

            if (castRequest.isConstantFolding())
                castRequest.setConstantFoldingResult(ConstantRef::invalid());
            return Result::Continue;
        }
    }

    return castRequest.fail(DiagnosticId::sema_err_cannot_cast_to_interface, srcTypeRef, dstTypeRef);
}

Result Cast::castFromAny(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (castRequest.kind != CastKind::Explicit)
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

    const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
    if (sema.typeMgr().get(srcTypeRef).isConst() &&
        (dstType.isReference() || dstType.isMoveReference() || dstType.isAnyPointer() || dstType.isSlice() || dstType.isCString() || dstType.isInterface()) &&
        !dstType.isConst() &&
        !castRequest.flags.has(CastFlagsE::UnConst))
        return castRequest.fail(DiagnosticId::sema_err_cannot_cast_const, srcTypeRef, dstTypeRef);

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
        const TypeInfo* enumType  = &valueType;
        if (!enumType->isEnum() && valueType.isAlias())
        {
            const TypeRef unwrappedTypeRef = valueType.unwrap(ctx, valueTypeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
            {
                const TypeInfo& unwrappedType = sema.typeMgr().get(unwrappedTypeRef);
                if (unwrappedType.isEnum())
                {
                    enumType = &unwrappedType;
                }
            }
        }

        if (enumType->isEnum())
        {
            const TypeRef       underlyingTypeRef = enumType->payloadSymEnum().underlyingTypeRef();
            const ConstantValue underlyingCst     = ConstantValue::make(ctx, runtimeAny.value, underlyingTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!underlyingCst.isValid())
                return castRequest.fail(DiagnosticId::sema_err_cannot_cast, srcTypeRef, dstTypeRef);

            const ConstantRef   underlyingCstRef = sema.cstMgr().addConstant(ctx, underlyingCst);
            const ConstantValue enumCst          = ConstantValue::makeEnumValue(ctx, underlyingCstRef, valueTypeRef);
            valueCstRef                          = sema.cstMgr().addConstant(ctx, enumCst);
        }
        else if (valueType.isAnyTypeInfo(ctx))
        {
            const uint64_t ptrValue = *static_cast<const uint64_t*>(runtimeAny.value);
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

    if ((dstType.isReference() || dstType.isMoveReference() || dstType.isAnyPointer()) &&
        dstType.isConst() &&
        dstType.payloadTypeRef() == valueTypeRef)
    {
        SWC_RESULT(constantFoldPointerLikeFromValue(sema, valueCstRef, valueTypeRef, dstTypeRef, castRequest.outConstRef));
        return Result::Continue;
    }

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

SWC_END_NAMESPACE();
