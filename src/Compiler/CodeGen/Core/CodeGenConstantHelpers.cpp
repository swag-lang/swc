#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool mergeRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, uint32_t candidateShardIndex)
    {
        if (!hasRequiredShard)
        {
            outShardIndex    = candidateShardIndex;
            hasRequiredShard = true;
            return true;
        }

        return outShardIndex == candidateShardIndex;
    }

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, CodeGen& codeGen, const void* ptr)
    {
        if (!ptr)
            return true;

        uint32_t  shardIndex = 0;
        const Ref targetRef  = codeGen.cstMgr().findDataSegmentRef(shardIndex, ptr);
        if (targetRef == INVALID_REF)
            return false;

        return mergeRequiredShardIndex(outShardIndex, hasRequiredShard, shardIndex);
    }

    bool resolveStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, CodeGen& codeGen, TypeRef typeRef, ByteSpan payload)
    {
        if (typeRef.isInvalid())
            return false;

        TaskContext&    ctx      = codeGen.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias);
            return unwrappedTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, unwrappedTypeRef, payload);
        }

        const uint64_t sizeOf = typeInfo.sizeOf(ctx);
        if (sizeOf != payload.size())
            return false;

        if (typeInfo.isEnum())
            return resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, typeInfo.payloadSymEnum().underlyingTypeRef(), payload);

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString() || typeInfo.isSlice())
            return true;

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
                const auto     elementBytes  = ByteSpan{payload.data() + elementOffset, static_cast<size_t>(elementSize)};
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
                const TypeInfo& fieldType    = ctx.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                const uint64_t  fieldOffset  = field->offset();
                if (fieldOffset + fieldSize > payload.size())
                    return false;

                const auto fieldBytes = ByteSpan{payload.data() + fieldOffset, static_cast<size_t>(fieldSize)};
                if (!resolveStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, codeGen, fieldTypeRef, fieldBytes))
                    return false;
            }

            return true;
        }

        if (typeInfo.isPointerLike() || typeInfo.isReference() || typeInfo.isTypeInfo() || typeInfo.isCString() || typeInfo.isFunction())
        {
            if (payload.size() != sizeof(uint64_t))
                return false;

            const uint64_t rawPtr = *reinterpret_cast<const uint64_t*>(payload.data());
            return requirePointerShardIndex(outShardIndex, hasRequiredShard, codeGen, reinterpret_cast<const void*>(rawPtr));
        }

        return false;
    }
}

ConstantRef CodeGenConstantHelpers::materializeStaticPayloadConstant(CodeGen& codeGen, TypeRef typeRef, ByteSpan payload)
{
    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    TaskContext&    ctx      = codeGen.ctx();
    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    const uint64_t  sizeOf   = typeInfo.sizeOf(ctx);
    if (sizeOf != payload.size())
        return ConstantRef::invalid();

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(shardIndex, hasRequiredShard, codeGen, typeRef, payload))
        return ConstantRef::invalid();

    DataSegment& segment = codeGen.cstMgr().shardDataSegment(hasRequiredShard ? shardIndex : 0);
    uint32_t     offset  = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, codeGen.sema(), segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    const ByteSpan storedBytes{segment.ptr<std::byte>(offset), sizeOf};
    if (typeInfo.isArray())
        return codeGen.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, typeRef, storedBytes));

    return codeGen.cstMgr().addConstant(ctx, ConstantValue::makeStructBorrowed(ctx, typeRef, storedBytes));
}

ConstantRef CodeGenConstantHelpers::materializeRuntimeBufferConstant(CodeGen& codeGen, TypeRef typeRef, const void* targetPtr, uint64_t count)
{
    uint32_t targetShardIndex = 0;
    Ref      targetOffset     = INVALID_REF;
    if (targetPtr)
        targetOffset = codeGen.cstMgr().findDataSegmentRef(targetShardIndex, targetPtr);

    if (targetPtr && targetOffset == INVALID_REF)
        return ConstantRef::invalid();

    DataSegment& segment         = codeGen.cstMgr().shardDataSegment(targetOffset == INVALID_REF ? 0 : targetShardIndex);
    const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::Slice<std::byte>), alignof(Runtime::Slice<std::byte>), true);
    auto* const runtimeValue     = reinterpret_cast<Runtime::Slice<std::byte>*>(storage);
    runtimeValue->ptr            = const_cast<std::byte*>(static_cast<const std::byte*>(targetPtr));
    runtimeValue->count          = count;

    if (targetOffset != INVALID_REF)
        segment.addRelocation(offset + offsetof(Runtime::Slice<std::byte>, ptr), targetOffset);

    const ConstantValue runtimeValueCst = ConstantValue::makeStructBorrowed(codeGen.ctx(), typeRef, ByteSpan{storage, sizeof(Runtime::Slice<std::byte>)});
    return codeGen.cstMgr().addConstant(codeGen.ctx(), runtimeValueCst);
}

SWC_END_NAMESPACE();
