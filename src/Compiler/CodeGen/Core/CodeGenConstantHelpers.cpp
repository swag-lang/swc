#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, CodeGen& codeGen, const void* ptr)
    {
        if (!ptr)
            return true;

        DataSegmentRef ref;
        if (!codeGen.cstMgr().resolveDataSegmentRef(ref, ptr))
            return false;

        return mergeRequiredShardIndex(outShardIndex, hasRequiredShard, ref.shardIndex);
    }

    bool hasSourceFunctionRelocation(CodeGen& codeGen, const void* fieldPtr)
    {
        DataSegmentRef sourceRef;
        if (!codeGen.cstMgr().resolveDataSegmentRef(sourceRef, fieldPtr))
            return false;

        DataSegmentRelocation relocation;
        return codeGen.cstMgr().shardDataSegment(sourceRef.shardIndex).findRelocation(relocation, sourceRef.offset, DataSegmentRelocationKind::FunctionSymbol);
    }

    bool resolveClosureStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, CodeGen& codeGen, std::span<const std::byte> payload)
    {
        if (payload.size() != sizeof(Runtime::ClosureValue))
            return false;

        const auto* runtimeClosure = reinterpret_cast<const Runtime::ClosureValue*>(payload.data());
        if (!requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, runtimeClosure->invoke))
            return false;

        const auto capturedTarget = reinterpret_cast<const void*>(*reinterpret_cast<const uint64_t*>(runtimeClosure->capture));
        return requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, capturedTarget);
    }

    bool resolveStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> payload)
    {
        if (typeRef.isInvalid())
            return false;

        TaskContext&       ctx      = codeGen.ctx();
        const TypeManager& typeMgr  = ctx.typeMgr();
        const TypeInfo&    typeInfo = typeMgr.get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, unwrappedTypeRef, payload);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != payload.size())
            return false;

        if (typeInfo.isTypeValue())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, typeInfo.payloadTypeRef(), payload);

        if (typeInfo.isEnum())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, typeInfo.payloadSymEnum().underlyingTypeRef(), payload);

        if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
            return resolveClosureStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, payload);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString())
            return true;

        if (typeInfo.isSlice())
        {
            if (payload.size() != sizeof(Runtime::Slice<std::byte>))
                return false;

            const auto*     runtimeSlice   = reinterpret_cast<const Runtime::Slice<std::byte>*>(payload.data());
            const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo& elementType    = typeMgr.get(elementTypeRef);
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
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, elementTypeRef, elementBytes))
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

            return requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, runtimeAny->type);
        }

        if (typeInfo.isInterface())
        {
            if (payload.size() != sizeof(Runtime::Interface))
                return false;

            const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(payload.data());
            return requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, runtimeInterface->obj) &&
                   requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, runtimeInterface->itable);
        }

        if (typeInfo.isArray())
        {
            const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
            const TypeInfo& elementType    = typeMgr.get(elementTypeRef);
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
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, elementTypeRef, elementBytes))
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
                const TypeInfo& fieldType    = typeMgr.get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                if (fieldOffset + fieldSize > payload.size())
                    return false;

                const auto fieldBytes = std::span{payload.data() + fieldOffset, static_cast<size_t>(fieldSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, fieldTypeRef, fieldBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
        {
            uint64_t offset = 0;
            for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
            {
                const TypeInfo& fieldType = typeMgr.get(fieldTypeRef);
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
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, fieldTypeRef, fieldBytes))
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
            if (requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, reinterpret_cast<const void*>(rawPtr)))
                return true;

            return hasSourceFunctionRelocation(codeGen, payload.data());
        }

        return false;
    }

    ConstantValue makeMaterializedConstantValue(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> storedBytes, DataSegmentRef dataSegmentRef)
    {
        TaskContext&    ctx            = codeGen.ctx();
        const TypeInfo& originalType   = ctx.typeMgr().get(typeRef);
        TypeRef         storageTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isInvalid())
            storageTypeRef = typeRef;

        const TypeInfo& storageType = ctx.typeMgr().get(storageTypeRef);
        ConstantValue   result;

        if (storageType.isArray())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isBool() || storageType.isChar() || storageType.isRune() || storageType.isInt() || storageType.isFloat() || storageType.isAnyPointer() || storageType.isReference() || storageType.isTypeInfo() || storageType.isCString() || (storageType.isFunction() && !storageType.isLambdaClosure()))
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        else
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);

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
            const ConstantRef storageRef = codeGen.cstMgr().addConstant(ctx, result);
            return ConstantValue::makeEnumValue(ctx, storageRef, typeRef);
        }

        result.setTypeRef(typeRef);
        return result;
    }
}

ConstantRef CodeGenConstantHelpers::ensureStaticPayloadConstant(CodeGen& codeGen, const ConstantRef cstRef, TypeRef typeRef)
{
    if (!cstRef.isValid())
        return ConstantRef::invalid();

    const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
    if (typeRef.isInvalid())
        typeRef = cst.typeRef();

    std::span<const std::byte> payload;
    if (cst.isStruct())
        payload = cst.getStruct();
    else if (cst.isArray())
        payload = cst.getArray();
    else
        return cstRef;

    if (cst.isPayloadBorrowed())
    {
        DataSegmentRef payloadRef;
        if (codeGen.cstMgr().resolveConstantDataSegmentRef(payloadRef, cstRef, payload.data()))
            return cstRef;
    }

    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    TaskContext&    ctx      = codeGen.ctx();
    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
    if (sizeOf != payload.size())
        return ConstantRef::invalid();

    SmallVector<std::byte> storageBytes;
    storageBytes.resize(sizeOf);
    if (sizeOf)
        SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(codeGen.sema(), std::span{storageBytes.data(), storageBytes.size()}, cstRef, typeRef) == Result::Continue);

    return materializeStaticPayloadConstant(codeGen, typeRef, std::span{storageBytes.data(), storageBytes.size()});
}

ConstantRef CodeGenConstantHelpers::materializeStaticArrayBufferConstant(CodeGen& codeGen, const TypeRef elementTypeRef, const std::span<const std::byte> payload, const uint64_t count)
{
    if (elementTypeRef.isInvalid())
        return ConstantRef::invalid();

    SmallVector<uint64_t> dims;
    dims.push_back(count);
    const TypeRef arrayTypeRef = codeGen.typeMgr().addType(TypeInfo::makeArray(dims.span(), elementTypeRef));
    return materializeStaticPayloadConstant(codeGen, arrayTypeRef, payload);
}

ConstantRef CodeGenConstantHelpers::materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, std::span<const std::byte> payload)
{
    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    TaskContext&    ctx      = codeGen.ctx();
    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
    if (sizeOf != payload.size())
        return ConstantRef::invalid();

    const TypeRef   storageTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    const TypeInfo& storageType    = ctx.typeMgr().get(storageTypeRef.isValid() ? storageTypeRef : typeRef);
    if (storageType.isStruct() && storageType.payloadSymStruct().isUnion())
        return codeGen.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeRef, payload));

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(shardIndex, hasRequiredShard, codeGen, typeRef, payload))
        return ConstantRef::invalid();

    DataSegment& segment = codeGen.cstMgr().shardDataSegment(hasRequiredShard ? shardIndex : 0);
    uint32_t     offset  = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, codeGen.sema(), segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    SWC_ASSERT(sizeOf != 0 || offset == INVALID_REF);
    const std::span<const std::byte> storedBytes = sizeOf ? std::span{segment.ptr<std::byte>(offset), sizeOf} : std::span<const std::byte>{};
    const DataSegmentRef             dataRef{.shardIndex = hasRequiredShard ? shardIndex : 0, .offset = offset};
    const ConstantValue              value = makeMaterializedConstantValue(codeGen, typeRef, storedBytes, dataRef);
    if (!value.isValid())
        return ConstantRef::invalid();

    if (dataRef.isValid() && (value.isStruct() || value.isArray() || value.isSlice()) && value.isPayloadBorrowed())
        return codeGen.cstMgr().addMaterializedPayloadConstant(value);

    return codeGen.cstMgr().addConstant(ctx, value);
}

ConstantRef CodeGenConstantHelpers::materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count)
{
    ConstantManager&  cstMgr          = codeGen.cstMgr();
    const uint32_t    cacheShardIndex = ConstantManager::runtimeBufferConstantCacheShard(typeRef, targetPtr, count);
    const ConstantRef cached          = cstMgr.findRuntimeBufferConstant(cacheShardIndex, typeRef, targetPtr, count);
    if (cached.isValid())
        return cached;

    DataSegmentRef targetRef;
    if (targetPtr)
        cstMgr.resolveDataSegmentRef(targetRef, targetPtr);

    if (targetPtr && targetRef.isInvalid())
        return ConstantRef::invalid();

    const uint32_t shardIndex    = targetRef.isInvalid() ? 0 : targetRef.shardIndex;
    DataSegment&   segment       = cstMgr.shardDataSegment(shardIndex);
    const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::Slice<std::byte>), alignof(Runtime::Slice<std::byte>), true);
    auto* runtimeValue           = reinterpret_cast<Runtime::Slice<std::byte>*>(storage);
    runtimeValue->ptr            = const_cast<std::byte*>(static_cast<const std::byte*>(targetPtr));
    runtimeValue->count          = count;

    if (targetRef.isValid())
        segment.addRelocation(offset + offsetof(Runtime::Slice<std::byte>, ptr), targetRef.offset);

    ConstantValue runtimeValueCst = ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, std::span{storage, sizeof(Runtime::Slice<std::byte>)});
    runtimeValueCst.setDataSegmentRef({.shardIndex = shardIndex, .offset = offset});
    const ConstantRef cstRef = cstMgr.addUniqueMaterializedPayloadConstant(runtimeValueCst);
    return cstMgr.publishRuntimeBufferConstant(cacheShardIndex, typeRef, targetPtr, count, cstRef);
}

ConstantRef CodeGenConstantHelpers::materializeRuntimeStringConstant(CodeGen& codeGen, TypeRef typeRef, const std::string_view value)
{
    ConstantManager&  cstMgr          = codeGen.cstMgr();
    const uint32_t    cacheShardIndex = ConstantManager::runtimeStringConstantCacheShard(typeRef, value);
    const ConstantRef cached          = cstMgr.findRuntimeStringConstant(cacheShardIndex, typeRef, value);
    if (cached.isValid())
        return cached;

    const std::string_view storedValue = cstMgr.addString(codeGen.ctx(), value);
    const ConstantRef      cstRef      = materializeRuntimeBufferConstant(codeGen, typeRef, storedValue.data(), storedValue.size());
    if (cstRef.isInvalid())
        return ConstantRef::invalid();

    return cstMgr.publishRuntimeStringConstant(cacheShardIndex, typeRef, value, cstRef);
}

Result CodeGenConstantHelpers::loadTypeInfoConstantReg(MicroReg& outReg, CodeGen& codeGen, TypeRef typeRef)
{
    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(codeGen.cstMgr().makeTypeInfo(codeGen.sema(), typeInfoCstRef, typeRef, codeGen.curNodeRef()));
    const ConstantValue& typeInfoCst = codeGen.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());

    outReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(outReg, typeInfoCst.getValuePointer(), typeInfoCstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
