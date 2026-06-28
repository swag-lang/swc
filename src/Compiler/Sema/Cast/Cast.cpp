#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef aggregateArraySliceStorageTypeRef(Sema& sema, const TypeInfo& srcType, const TypeInfo& dstType)
    {
        if (!srcType.isAggregateArray() || !dstType.isSlice())
            return TypeRef::invalid();

        SmallVector4<uint64_t> dims;
        dims.push_back(srcType.payloadAggregate().types.size());
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, dstType.payloadTypeRef()));
    }

    AstNodeRef fallbackCastFailureNodeRef(Sema& sema, const CastFailure& failure)
    {
        if (failure.nodeRef.isValid())
            return failure.nodeRef;

        const AstNodeRef stateNodeRef = sema.ctx().state().nodeRef;
        if (stateNodeRef.isValid())
            return stateNodeRef;

        return sema.curNodeRef();
    }

    TypeRef castSourceRuntimeStorageTypeRef(Sema& sema, AstNodeRef srcNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
    {
        if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
            return TypeRef::invalid();

        const TypeRef   dstStorageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), dstTypeRef);
        const TypeInfo& dstType           = sema.typeMgr().get(dstStorageTypeRef);
        if (!dstType.isSlice() && !dstType.isString())
            return TypeRef::invalid();

        return SemaHelpers::smallByValueArrayRuntimeStorageTypeRef(sema, srcNodeRef, srcTypeRef, srcConstRef);
    }

    bool isPointerLikeInterfaceObjectSource(Sema& sema, const TypeInfo& srcType)
    {
        if (!srcType.isAnyPointer() && !srcType.isReference() && !srcType.isMoveReference())
            return false;

        const TypeRef objectTypeRef = sema.typeMgr().get(srcType.payloadTypeRef()).unwrapAliasEnum(sema.ctx(), srcType.payloadTypeRef());
        if (!objectTypeRef.isValid())
            return false;

        return sema.typeMgr().get(objectTypeRef).isStruct();
    }

    bool isByValueAggregateType(const TypeInfo& typeInfo)
    {
        return typeInfo.isStruct() || typeInfo.isArray() || typeInfo.isAggregate();
    }

}

TypeRef Cast::indirectValueCastTypeRef(const Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef)
{
    if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
        return TypeRef::invalid();

    const TypeRef   srcResolvedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), srcTypeRef);
    const TypeRef   dstResolvedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), dstTypeRef);
    const TypeRef   srcTypeToCheck     = srcResolvedTypeRef.isValid() ? srcResolvedTypeRef : srcTypeRef;
    const TypeRef   dstTypeToCheck     = dstResolvedTypeRef.isValid() ? dstResolvedTypeRef : dstTypeRef;
    const TypeInfo& srcType            = sema.typeMgr().get(srcTypeToCheck);
    const TypeInfo& dstType            = sema.typeMgr().get(dstTypeToCheck);

    TypeRef valueTypeRef;
    bool    sourceIsPointer = false;
    if (srcType.isReference())
    {
        valueTypeRef = srcType.payloadTypeRef();
    }
    else if (srcType.isAnyPointer() && !srcType.isNullable())
    {
        valueTypeRef    = srcType.payloadTypeRef();
        sourceIsPointer = true;
    }
    else
        return TypeRef::invalid();

    if (sourceIsPointer && !isByValueAggregateType(dstType))
        return TypeRef::invalid();

    if (valueTypeRef == dstTypeRef)
        return valueTypeRef;

    if (sema.typeMgr().get(dstTypeRef).isAlias())
        return TypeRef::invalid();

    const TypeRef valueResolvedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), valueTypeRef);
    const TypeRef valueTypeToCheck     = valueResolvedTypeRef.isValid() ? valueResolvedTypeRef : valueTypeRef;
    if (valueTypeToCheck == dstTypeToCheck)
        return valueTypeRef;

    return TypeRef::invalid();
}

TypeRef Cast::runtimeStorageTypeRef(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
{
    if (!srcTypeRef.isValid() || !dstTypeRef.isValid())
        return TypeRef::invalid();

    const TypeRef   srcStorageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), srcTypeRef);
    const TypeRef   dstStorageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), dstTypeRef);
    const TypeInfo& srcType           = sema.typeMgr().get(srcStorageTypeRef);
    const TypeInfo& dstType           = sema.typeMgr().get(dstStorageTypeRef);

    if (srcConstRef.isValid())
    {
        if (dstType.isArray() && !srcType.isAggregate() && !srcType.isArray())
            return dstTypeRef;

        if (srcType.isStruct() && dstType.isInterface())
        {
            constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
            const uint64_t         valueStorage         = srcType.sizeOf(sema.ctx());
            SmallVector4<uint64_t> dims;
            dims.push_back(interfaceStorageSize + valueStorage);
            return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
        }

        if (isPointerLikeInterfaceObjectSource(sema, srcType) && dstType.isInterface())
        {
            SmallVector4<uint64_t> dims;
            dims.push_back(sizeof(Runtime::Interface));
            return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
        }
    }

    if (dstType.isStruct())
    {
        SymbolFunction* calledFn     = nullptr;
        TypeRef         paramTypeRef = TypeRef::invalid();
        const auto      codeRef      = sema.node(sema.curNodeRef()).codeRef();
        if (resolveStructSetCastCandidate(sema, codeRef, srcTypeRef, dstTypeRef, CastKind::Initialization, calledFn, paramTypeRef, sema.curNodeRef()) == Result::Continue && calledFn)
            return dstTypeRef;
    }

    if (srcConstRef.isValid())
        return TypeRef::invalid();

    if (indirectValueCastTypeRef(sema, srcTypeRef, dstTypeRef).isValid())
        return dstTypeRef;

    if (dstType.isReference() && !srcType.isPointerOrReference())
        return srcTypeRef;

    if (srcType.isAggregateArray() && dstType.isSlice())
        return dstTypeRef;

    if (srcType.isArray() && (dstType.isSlice() || dstType.isString()))
        return dstTypeRef;

    if (srcType.isCString() && (dstType.isSlice() || dstType.isString()))
        return dstTypeRef;

    if (!srcType.isAny() && dstType.isAny())
    {
        constexpr uint64_t     anyStorageSize = sizeof(Runtime::Any);
        const uint64_t         valueStorage   = std::max<uint64_t>(1, srcType.sizeOf(sema.ctx()));
        SmallVector4<uint64_t> dims;
        dims.push_back(anyStorageSize + valueStorage);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    if (srcType.isStruct() && dstType.isInterface())
    {
        constexpr uint64_t     interfaceStorageSize = sizeof(Runtime::Interface);
        const uint64_t         valueStorage         = srcType.sizeOf(sema.ctx());
        SmallVector4<uint64_t> dims;
        dims.push_back(interfaceStorageSize + valueStorage);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    if (isPointerLikeInterfaceObjectSource(sema, srcType) && dstType.isInterface())
    {
        SmallVector4<uint64_t> dims;
        dims.push_back(sizeof(Runtime::Interface));
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, sema.typeMgr().typeU8()));
    }

    if (srcType.isFunction() && dstType.isFunction() && !srcType.isLambdaClosure() && dstType.isLambdaClosure())
        return dstTypeRef;

    return TypeRef::invalid();
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    // Some callers propagate a pre-existing semantic error through the cast layer without
    // populating a cast-specific diagnostic. In that case, preserve the original failure.
    if (f.diagId == DiagnosticId::None)
        return Result::Error;

    Diagnostic diag;
    if (f.codeRef.isValid())
        diag = SemaError::report(sema, f.diagId, f.codeRef);
    else
    {
        const AstNodeRef errorNodeRef = fallbackCastFailureNodeRef(sema, f);
        if (errorNodeRef.isValid())
            diag = SemaError::report(sema, f.diagId, errorNodeRef);
        else
        {
            const SourceCodeRef stateCodeRef = sema.ctx().state().codeRef;
            SWC_ASSERT(stateCodeRef.isValid());
            diag = SemaError::report(sema, f.diagId, stateCodeRef);
        }
    }
    f.applyArguments(diag);
    if (f.noteId != DiagnosticId::None)
    {
        diag.addNote(f.noteId);
        f.applyArguments(diag.last());

        if (f.noteNodeRef.isValid())
        {
            diag.last().addSpan(sema.node(f.noteNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast()));
        }
        else if (f.noteCodeRef.isValid())
        {
            const SourceView& srcView = sema.ctx().compiler().srcView(f.noteCodeRef.srcViewRef);
            diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), f.noteCodeRef.tokRef));
        }
    }
    diag.report(sema.ctx());
    return Result::Error;
}

Result Cast::attachCastRuntimeStorageIfNeeded(Sema& sema, AstNodeRef castNodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, ConstantRef srcConstRef)
{
    if (sema.isGlobalScope())
        return Result::Continue;

    const auto& castNode = sema.node(castNodeRef);
    if (castNode.is(AstNodeId::CastExpr))
    {
        const AstNodeRef srcNodeRef           = castNode.cast<AstCastExpr>().nodeExprRef;
        const TypeRef    sourceStorageTypeRef = castSourceRuntimeStorageTypeRef(sema, srcNodeRef, srcTypeRef, dstTypeRef, srcConstRef);
        if (sourceStorageTypeRef.isValid())
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, srcNodeRef, sema.node(srcNodeRef), sourceStorageTypeRef, "__cast_source_runtime_storage"));
    }

    const TypeRef storageTypeRef = runtimeStorageTypeRef(sema, srcTypeRef, dstTypeRef, srcConstRef);
    if (storageTypeRef.isInvalid())
        return Result::Continue;

    auto& storageSym = SemaHelpers::getOrCreateRuntimeStorageSymbol(sema, castNodeRef, sema.node(castNodeRef), "__cast_runtime_storage");
    return SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, storageTypeRef);
}

Result Cast::retargetLiteralRuntimeStorageIfNeeded(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef dstTypeRef, bool createIfMissing)
{
    if (srcTypeRef.isInvalid() || dstTypeRef.isInvalid())
        return Result::Continue;

    const TypeRef   srcStorageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), srcTypeRef);
    const TypeRef   dstStorageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), dstTypeRef);
    const TypeInfo& srcType           = sema.typeMgr().get(srcStorageTypeRef);
    const TypeInfo& dstType           = sema.typeMgr().get(dstStorageTypeRef);
    const bool      needsRetarget =
        (srcType.isAggregateArray() && (dstType.isArray() || dstType.isSlice())) ||
        (srcType.isAggregateStruct() && dstType.isStruct());
    if (!needsRetarget)
        return Result::Continue;

    TypeRef storageTypeRef = dstTypeRef;
    if (srcType.isAggregateArray() && dstType.isSlice())
        storageTypeRef = aggregateArraySliceStorageTypeRef(sema, srcType, dstType);
    if (storageTypeRef.isInvalid())
        return Result::Continue;

    const auto* payload = sema.loweringPayload<CodeGenLoweringPayload>(nodeRef);
    if (payload && payload->runtimeStorageSym != nullptr)
    {
        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&storageType, nodeRef));
        payload->runtimeStorageSym->setTypeRef(storageTypeRef);
        return Result::Continue;
    }

    if (!createIfMissing)
        return Result::Continue;

    return SemaHelpers::attachRuntimeStorageIfNeeded(sema, nodeRef, sema.node(nodeRef), storageTypeRef, "__literal_runtime_storage");
}

bool resolveDynamicStructCastSourceInfo(Sema& sema, AstNodeRef sourceRef, TypeRef sourceTypeRef, DynamicStructCastSourceInfo& outInfo)
{
    outInfo = {};
    if (!sourceTypeRef.isValid())
        return false;

    const TypeRef   resolvedSourceTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), sourceTypeRef);
    const TypeInfo& sourceType            = sema.typeMgr().get(resolvedSourceTypeRef);

    if (sourceType.isInterface())
    {
        outInfo.kind          = DynamicStructCastSourceKind::Interface;
        outInfo.sourceIsConst = sourceType.isConst();
        return true;
    }

    if (sourceType.isAny())
    {
        outInfo.kind          = DynamicStructCastSourceKind::Any;
        outInfo.sourceIsConst = sourceType.isConst();
        return true;
    }

    if (sourceType.isPointerOrReference())
    {
        const TypeRef   pointeeTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), sourceType.payloadTypeRef());
        const TypeInfo& pointeeType    = sema.typeMgr().get(pointeeTypeRef);
        if (pointeeType.isStruct())
        {
            outInfo.kind          = DynamicStructCastSourceKind::StructPointerLike;
            outInfo.structTypeRef = pointeeTypeRef;
            outInfo.sourceIsConst = sourceType.isConst();
            return true;
        }
    }

    if (!sema.isLValue(sourceRef))
        return false;

    const TypeRef   structTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), resolvedSourceTypeRef);
    const TypeInfo& structType    = sema.typeMgr().get(structTypeRef);
    if (!structType.isStruct())
        return false;

    outInfo.kind          = DynamicStructCastSourceKind::StructAddress;
    outInfo.structTypeRef = structTypeRef;
    outInfo.sourceIsConst = structType.isConst();
    return true;
}

AstNodeRef Cast::createCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef, AstCastExprFlagsE castFlags)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::CastExpr>(node.tokRef());
    substNodePtr->addFlag(castFlags);
    substNodePtr->setCodeRef(node.codeRef());
    substNodePtr->nodeTypeRef = AstNodeRef::invalid();
    substNodePtr->nodeExprRef = nodeRef;
    sema.setSubstitute(nodeRef, substNodeRef);
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

AstNodeRef Cast::createCastNode(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef, AstCastExprFlagsE castFlags)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::CastExpr>(node.tokRef());
    substNodePtr->addFlag(castFlags);
    substNodePtr->setCodeRef(node.codeRef());
    substNodePtr->nodeTypeRef = AstNodeRef::invalid();
    substNodePtr->nodeExprRef = nodeRef;
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
