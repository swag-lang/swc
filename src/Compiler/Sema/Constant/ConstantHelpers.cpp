#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef constantFoldStorageTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAlias() && !typeInfo.isEnum())
            return typeRef;

        const TypeRef storageTypeRef = typeInfo.unwrapAliasEnum(sema.ctx(), typeRef);
        return storageTypeRef.isValid() ? storageTypeRef : typeRef;
    }

    uint32_t sourceCodeLocationShardIndex(const SourceCodeRange& codeRange, const SymbolFunction* function)
    {
        uint32_t hash = Math::hash(codeRange.srcView ? codeRange.srcView->ref().get() : 0);
        hash          = Math::hashCombine(hash, reinterpret_cast<uint64_t>(function));
        hash          = Math::hashCombine(hash, codeRange.line);
        hash          = Math::hashCombine(hash, codeRange.column);
        hash          = Math::hashCombine(hash, codeRange.len);
        return hash & (ConstantManager::SHARD_COUNT - 1);
    }

    Result waitStaticPayloadTypeReadyRec(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, std::unordered_set<TypeRef>& visited);

    Result waitStaticPayloadTypeReadyRecImpl(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, std::unordered_set<TypeRef>& visited)
    {
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);

        if (typeInfo.isAlias())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, waitNodeRef));
            return waitStaticPayloadTypeReadyRec(sema, typeInfo.payloadTypeRef(), waitNodeRef, visited);
        }

        if (typeInfo.isEnum())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, waitNodeRef));
            return waitStaticPayloadTypeReadyRec(sema, typeInfo.payloadSymEnum().underlyingTypeRef(), waitNodeRef, visited);
        }

        if (typeInfo.isTypeValue())
            return waitStaticPayloadTypeReadyRec(sema, typeInfo.payloadTypeRef(), waitNodeRef, visited);

        if (typeInfo.isSlice())
            return waitStaticPayloadTypeReadyRec(sema, typeInfo.payloadTypeRef(), waitNodeRef, visited);

        if (typeInfo.isArray())
            return waitStaticPayloadTypeReadyRec(sema, typeInfo.payloadArrayElemTypeRef(), waitNodeRef, visited);

        if (typeInfo.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, waitNodeRef));
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (field)
                    SWC_RESULT(waitStaticPayloadTypeReadyRec(sema, field->typeRef(), waitNodeRef, visited));
            }

            return Result::Continue;
        }

        if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
        {
            for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
                SWC_RESULT(waitStaticPayloadTypeReadyRec(sema, fieldTypeRef, waitNodeRef, visited));
        }

        return Result::Continue;
    }

    Result waitStaticPayloadTypeReadyRec(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, std::unordered_set<TypeRef>& visited)
    {
        if (typeRef.isInvalid())
            return Result::Continue;
        if (!visited.insert(typeRef).second)
            return Result::Continue;

        const Result result = waitStaticPayloadTypeReadyRecImpl(sema, typeRef, waitNodeRef, visited);
        visited.erase(typeRef);
        return result;
    }

    ConstantValue makeMaterializedConstantValue(Sema& sema, TypeRef typeRef, std::span<const std::byte> storedBytes, DataSegmentRef dataSegmentRef)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeInfo& originalType   = ctx.typeMgr().get(typeRef);
        TypeRef         storageTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isInvalid())
            storageTypeRef = typeRef;

        const TypeInfo& storageType = ctx.typeMgr().get(storageTypeRef);
        ConstantValue   result;

        if (storageType.isStruct() || storageType.isAny() || storageType.isInterface() || storageType.isAggregateStruct() || storageType.isAggregateArray() || (storageType.isFunction() && storageType.isLambdaClosure()))
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isArray())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);

        if (!result.isValid())
            return result;

        result.setDataSegmentRef(dataSegmentRef);
        bool isEnumValue = originalType.isEnum();
        if (!isEnumValue && originalType.isAlias())
        {
            const TypeRef unwrappedTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
                isEnumValue = ctx.typeMgr().get(unwrappedTypeRef).isEnum();
        }

        if (isEnumValue)
        {
            const ConstantRef storageRef = sema.cstMgr().addConstant(ctx, result);
            return ConstantValue::makeEnumValue(ctx, storageRef, typeRef);
        }

        result.setTypeRef(typeRef);
        return result;
    }

    bool mergeRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, uint32_t candidateShardIndex)
    {
        if (!hasRequiredShard)
        {
            outShardIndex    = candidateShardIndex;
            hasRequiredShard = true;
        }

        // Payload materialization can now relocate across shards, so this is
        // only a placement preference for the owning allocation.
        return true;
    }

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, const void* ptr)
    {
        if (!ptr)
            return true;

        DataSegmentRef ref;
        if (!sema.cstMgr().resolveDataSegmentRef(ref, ptr))
            return false;

        return mergeRequiredShardIndex(outShardIndex, hasRequiredShard, ref.shardIndex);
    }

    bool hasSourceFunctionRelocation(Sema& sema, const void* fieldPtr)
    {
        DataSegmentRef sourceRef;
        if (!sema.cstMgr().resolveDataSegmentRef(sourceRef, fieldPtr))
            return false;

        DataSegmentRelocation relocation;
        return sema.cstMgr().shardDataSegment(sourceRef.shardIndex).findRelocation(relocation, sourceRef.offset, DataSegmentRelocationKind::FunctionSymbol);
    }

    bool resolveClosureStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, std::span<const std::byte> payload)
    {
        if (payload.size() != sizeof(Runtime::ClosureValue))
            return false;

        const auto* runtimeClosure = reinterpret_cast<const Runtime::ClosureValue*>(payload.data());
        if (!requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeClosure->invoke))
            return false;

        const auto capturedTarget = reinterpret_cast<const void*>(*reinterpret_cast<const uint64_t*>(runtimeClosure->capture));
        return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, capturedTarget);
    }

    bool resolveStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, TypeRef typeRef, std::span<const std::byte> payload)
    {
        if (typeRef.isInvalid())
            return false;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, unwrappedTypeRef, payload);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != payload.size())
            return false;

        if (typeInfo.isTypeValue())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, typeInfo.payloadTypeRef(), payload);

        if (typeInfo.isEnum())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, typeInfo.payloadSymEnum().underlyingTypeRef(), payload);

        if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
            return resolveClosureStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, payload);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString())
            return true;

        if (typeInfo.isSlice())
        {
            if (payload.size() != sizeof(Runtime::Slice<std::byte>))
                return false;

            const auto*     runtimeSlice   = reinterpret_cast<const Runtime::Slice<std::byte>*>(payload.data());
            const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo& elementType    = ctx.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            if (runtimeSlice->count == 0 || elementSize == 0)
                return true;
            if (!runtimeSlice->ptr)
                return false;

            SWC_ASSERT(runtimeSlice->count <= std::numeric_limits<uint64_t>::max() / elementSize);
            for (uint64_t idx = 0; idx < runtimeSlice->count; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                const auto     elementBytes  = std::span{reinterpret_cast<const std::byte*>(runtimeSlice->ptr) + elementOffset, static_cast<size_t>(elementSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, elementTypeRef, elementBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isAny())
        {
            if (payload.size() != sizeof(Runtime::Any))
                return false;

            const auto* runtimeAny = reinterpret_cast<const Runtime::Any*>(payload.data());
            if (!runtimeAny->type)
                return runtimeAny->value == nullptr;

            return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeAny->type);
        }

        if (typeInfo.isInterface())
        {
            if (payload.size() != sizeof(Runtime::Interface))
                return false;

            const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(payload.data());
            return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->obj) &&
                   requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->itable);
        }

        if (typeInfo.isArray())
        {
            const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            const TypeInfo& elementType    = ctx.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            if (!elementSize)
                return payload.empty();

            uint64_t totalCount = 1;
            for (const uint64_t dim : typeInfo.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
            {
                const uint64_t elementOffset = idx * elementSize;
                const auto     elementBytes  = std::span{payload.data() + elementOffset, static_cast<size_t>(elementSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, elementTypeRef, elementBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isStruct())
        {
            for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
            {
                if (!field)
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = ctx.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                if (fieldOffset + fieldSize > payload.size())
                    return false;

                const auto fieldBytes = std::span{payload.data() + fieldOffset, static_cast<size_t>(fieldSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, fieldTypeRef, fieldBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
        {
            uint64_t offset = 0;
            for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
            {
                const TypeInfo& fieldType = ctx.typeMgr().get(fieldTypeRef);
                uint32_t        align     = fieldType.alignOf(ctx);
                const uint64_t  fieldSize = fieldType.sizeOf(ctx);
                if (!align)
                    align = 1;

                if (!fieldSize)
                    continue;

                offset = Math::alignUpU64(offset, align);
                if (offset + fieldSize > payload.size())
                    return false;

                const auto fieldBytes = std::span{payload.data() + offset, static_cast<size_t>(fieldSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, fieldTypeRef, fieldBytes))
                    return false;

                offset += fieldSize;
            }

            return true;
        }

        if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
        {
            if (payload.size() != sizeof(uint64_t))
                return false;

            const uint64_t rawPtr = *reinterpret_cast<const uint64_t*>(payload.data());
            if (requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, reinterpret_cast<const void*>(rawPtr)))
                return true;

            return hasSourceFunctionRelocation(sema, payload.data());
        }

        return false;
    }
}

Result ConstantHelpers::waitStaticPayloadTypeReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef)
{
    std::unordered_set<TypeRef> visited;
    return waitStaticPayloadTypeReadyRec(sema, typeRef, waitNodeRef, visited);
}

uint64_t ConstantHelpers::materializeConstantStorageAndGetAddress(Sema& sema, const SemaNodeView& view)
{
    SWC_ASSERT(view.type());
    TypeRef storageTypeRef = constantFoldStorageTypeRef(sema, view.typeRef());
    if (view.cstRef().isValid())
    {
        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        if (storageType.isScalarUnsized())
        {
            ConstantRef concretizedCstRef = ConstantRef::invalid();
            SWC_INTERNAL_CHECK(Cast::concretizeConstant(sema, concretizedCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unknown) == Result::Continue);
            if (concretizedCstRef.isValid())
                storageTypeRef = sema.cstMgr().get(concretizedCstRef).typeRef();
        }

        storageTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, storageTypeRef, view.cstRef());
    }

    const uint64_t sizeOf = sema.typeMgr().get(storageTypeRef).sizeOf(sema.ctx());
    if (!sizeOf)
        return 0;

    SmallVector<std::byte> storage(sizeOf);
    const std::span        storageSpan{storage.data(), storage.size()};
    std::memset(storageSpan.data(), 0, storageSpan.size());
    SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, storageSpan, view.cstRef(), storageTypeRef) == Result::Continue);

    const std::string_view persistentStorage = sema.cstMgr().addPayloadBuffer(std::string_view{reinterpret_cast<const char*>(storageSpan.data()), storageSpan.size()});
    return reinterpret_cast<uint64_t>(persistentStorage.data());
}

ConstantRef ConstantHelpers::materializeStaticPayloadConstant(Sema& sema, TypeRef typeRef, std::span<const std::byte> payload)
{
    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    TaskContext&    ctx      = sema.ctx();
    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
    if (sizeOf != payload.size())
        return ConstantRef::invalid();

    const TypeRef   storageTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    const TypeInfo& storageType    = ctx.typeMgr().get(storageTypeRef.isValid() ? storageTypeRef : typeRef);
    if (storageType.isStruct() && storageType.payloadSymStruct().isUnion())
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeRef, payload));

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(shardIndex, hasRequiredShard, sema, typeRef, payload))
        return ConstantRef::invalid();

    DataSegment& segment = sema.cstMgr().shardDataSegment(hasRequiredShard ? shardIndex : 0);
    uint32_t     offset  = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, sema, segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    SWC_ASSERT(sizeOf != 0 || offset == INVALID_REF);
    const DataSegmentRef             dataRef{.shardIndex = hasRequiredShard ? shardIndex : 0, .offset = offset};
    const std::span<const std::byte> storedBytes = sizeOf ? std::span{segment.ptr<std::byte>(offset), sizeOf} : std::span<const std::byte>{};
    const ConstantValue              result      = makeMaterializedConstantValue(sema, typeRef, storedBytes, dataRef);
    if (!result.isValid())
        return ConstantRef::invalid();

    if (dataRef.isValid() && (result.isStruct() || result.isArray() || result.isSlice()) && result.isPayloadBorrowed())
        return sema.cstMgr().addMaterializedPayloadConstant(result);

    return sema.cstMgr().addConstant(ctx, result);
}

Result ConstantHelpers::makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const SourceCodeRange& codeRange, const SymbolFunction* function)
{
    outCstRef = ConstantRef::invalid();

    const TaskContext& ctx     = sema.ctx();
    TypeRef            typeRef = TypeRef::invalid();
    SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, SourceCodeRef::invalid()));

    const SourceView* srcView  = codeRange.srcView;
    const SourceFile* file     = srcView ? srcView->file() : nullptr;
    const Utf8        fileName = file ? Utf8(file->path().string()) : Utf8{};
    const Utf8        funcName = function ? function->getFullScopedName(ctx) : Utf8{};

    const uint32_t shardIndex = sourceCodeLocationShardIndex(codeRange, function);
    DataSegment&   segment    = sema.cstMgr().shardDataSegment(shardIndex);

    const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::SourceCodeLocation), alignof(Runtime::SourceCodeLocation), true);
    auto* rtLoc                  = reinterpret_cast<Runtime::SourceCodeLocation*>(storage);

    rtLoc->fileName.length = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, fileName.ptr), fileName);

    if (funcName.empty())
    {
        rtLoc->funcName.ptr    = nullptr;
        rtLoc->funcName.length = 0;
    }
    else
    {
        rtLoc->funcName.length = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, funcName.ptr), funcName);
    }

    rtLoc->lineStart = codeRange.line;
    rtLoc->colStart  = codeRange.column;
    rtLoc->lineEnd   = codeRange.line;
    rtLoc->colEnd    = codeRange.column + codeRange.len;

    const auto    bytes  = std::span{storage, sizeof(Runtime::SourceCodeLocation)};
    ConstantValue cstVal = ConstantValue::makeStructBorrowed(ctx, typeRef, bytes);
    cstVal.setDataSegmentRef({.shardIndex = shardIndex, .offset = offset});
    outCstRef = sema.cstMgr().addUniqueMaterializedPayloadConstant(cstVal);
    return Result::Continue;
}

Result ConstantHelpers::makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const AstNode& node, const SymbolFunction* function)
{
    const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
    return makeSourceCodeLocation(sema, outCstRef, codeRange, function);
}

SWC_END_NAMESPACE();
