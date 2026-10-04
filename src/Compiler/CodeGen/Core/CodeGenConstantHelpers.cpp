#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Constant/ConstantEnumType.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ConstantValue makeMaterializedConstantValue(TaskContext& ctx, const TypeInfo& originalType, const TypeInfo& storageType, std::span<const std::byte> storedBytes, DataSegmentRef dataSegmentRef)
    {
        const TypeRef typeRef        = originalType.typeRef();
        const TypeRef storageTypeRef = storageType.typeRef();
        ConstantValue result;

        if (storageType.isArray() || storageType.isSimd())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isBool() || storageType.isChar() || storageType.isRune() || storageType.isInt() || storageType.isFloat() || storageType.isAnyPointer() || storageType.isReference() || storageType.isTypeInfo() || storageType.isCString() || (storageType.isFunction() && !storageType.isLambdaClosure()))
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        else
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);

        if (!result.isValid())
            return result;

        result.setDataSegmentRef(dataSegmentRef);
        if (ConstantHelpers::isEnumValueType(ctx, originalType, typeRef))
        {
            const ConstantRef storageRef = ctx.cstMgr().addConstant(ctx, result);
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

    const std::array<uint64_t, 1> dims         = {count};
    const TypeRef                 arrayTypeRef = codeGen.typeMgr().addType(TypeInfo::makeArray(dims, elementTypeRef));
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

    const TypeRef   storageTypeRef = typeInfo.isAlias() || typeInfo.isEnum() ? typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum) : typeRef;
    const TypeInfo& storageType    = storageTypeRef == typeRef ? typeInfo : ctx.typeMgr().get(storageTypeRef);
    if (storageType.isStruct() && storageType.payloadSymStruct().isUnion())
        return codeGen.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeRef, payload));

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!ConstantHelpers::resolveStaticPayloadRequiredShardIndex(codeGen.sema(), shardIndex, hasRequiredShard, typeInfo, payload))
        return ConstantRef::invalid();

    const uint32_t placementShardIndex = ConstantHelpers::staticPayloadPlacementShardIndex(ctx, typeRef, payload, hasRequiredShard, shardIndex);
    DataSegment&   segment             = codeGen.cstMgr().shardDataSegment(placementShardIndex);
    uint32_t       offset              = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, codeGen.sema(), segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    SWC_ASSERT(sizeOf != 0 || offset == INVALID_REF);
    const std::span<const std::byte> storedBytes = sizeOf ? std::span{segment.ptr<std::byte>(offset), sizeOf} : std::span<const std::byte>{};
    const DataSegmentRef             dataRef{.shardIndex = placementShardIndex, .offset = offset};
    const ConstantValue              value = makeMaterializedConstantValue(ctx, typeInfo, storageType, storedBytes, dataRef);
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

CodeGenNodePayload CodeGenConstantHelpers::makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
{
    const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
    SWC_ASSERT(cst.isStruct() || cst.isArray());

    const std::span<const std::byte> bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
    const uint64_t                   addr  = reinterpret_cast<uint64_t>(bytes.data());

    CodeGenNodePayload payload;
    payload.typeRef = cst.typeRef();
    payload.reg     = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(payload.reg, addr, cstRef);
    payload.setIsAddress();
    return payload;
}

SWC_END_NAMESPACE();
