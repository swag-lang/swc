#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantEnumType.h"
#include "Compiler/Sema/Constant/ConstantFoldStorage.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantShardPreference.h"
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

    Result waitStaticPayloadTypeReadyRecImpl(Sema& sema, const TypeInfo& typeInfo, AstNodeRef waitNodeRef, std::unordered_set<TypeRef>& visited)
    {
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
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        switch (typeInfo.kind())
        {
            case TypeInfoKind::Alias:
            case TypeInfoKind::Enum:
            case TypeInfoKind::TypeValue:
            case TypeInfoKind::Slice:
            case TypeInfoKind::Array:
            case TypeInfoKind::Struct:
            case TypeInfoKind::AggregateStruct:
            case TypeInfoKind::AggregateArray:
                break;
            default:
                return Result::Continue;
        }
        if (!visited.insert(typeRef).second)
            return Result::Continue;

        const Result result = waitStaticPayloadTypeReadyRecImpl(sema, typeInfo, waitNodeRef, visited);
        visited.erase(typeRef);
        return result;
    }

    ConstantValue makeMaterializedConstantValue(Sema& sema, TypeRef typeRef, std::span<const std::byte> storedBytes, DataSegmentRef dataSegmentRef)
    {
        TaskContext&    ctx            = sema.ctx();
        const TypeInfo& originalType   = ctx.typeMgr().get(typeRef);
        const TypeRef   storageTypeRef = originalType.isAlias() || originalType.isEnum() ? originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum) : typeRef;

        const TypeInfo& storageType = storageTypeRef == typeRef ? originalType : ctx.typeMgr().get(storageTypeRef);
        ConstantValue   result;

        if (storageType.isStruct() || storageType.isAny() || storageType.isInterface() || storageType.isAggregateStruct() || storageType.isAggregateArray() || (storageType.isFunction() && storageType.isLambdaClosure()))
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isArray() || storageType.isSimd())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);

        if (!result.isValid())
            return result;

        result.setDataSegmentRef(dataSegmentRef);
        if (ConstantHelpers::isEnumValueType(ctx, originalType, typeRef))
        {
            const ConstantRef storageRef = sema.cstMgr().addConstant(ctx, result);
            return ConstantValue::makeEnumValue(ctx, storageRef, typeRef);
        }

        result.setTypeRef(typeRef);
        return result;
    }

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, const void* ptr)
    {
        if (!ptr)
            return true;

        DataSegmentRef ref;
        if (!sema.cstMgr().resolveDataSegmentRef(ref, ptr))
            return false;

        return ConstantShardPreference::mergeRequiredShardIndex(outShardIndex, hasRequiredShard, ref.shardIndex);
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

        if (typeInfo.isBool() || typeInfo.isChar() || typeInfo.isRune() || typeInfo.isInt() || typeInfo.isFloat() || typeInfo.isString() || typeInfo.isSimd())
            return true;

        if (typeInfo.isSlice())
        {
            if (payload.size() != sizeof(Runtime::Slice<std::byte>))
                return false;

            // The empty test comes first: a slice element type never had to be laid out for the
            // enclosing payload to exist (a slice is two pointers whatever it points to), so its
            // size may legitimately not be computed yet — and must not be read — when the slice
            // carries nothing.
            const auto* runtimeSlice = reinterpret_cast<const Runtime::Slice<std::byte>*>(payload.data());
            if (runtimeSlice->count == 0)
                return true;

            const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
            const TypeInfo& elementType    = ctx.typeMgr().get(elementTypeRef);
            const uint64_t  elementSize    = elementType.sizeOf(ctx);
            if (elementSize == 0)
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

            return ConstantHelpers::hasSourceFunctionRelocation(sema, payload.data());
        }

        return false;
    }
    bool typeHasUnionStorageRec(const TaskContext& ctx, TypeRef typeRef, std::unordered_set<TypeRef>& visited)
    {
        typeRef              = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (!type.isArray() && !type.isStruct())
            return false;
        if (!visited.insert(typeRef).second)
            return false;
        if (type.isArray())
            return typeHasUnionStorageRec(ctx, type.payloadArrayElemTypeRef(), visited);
        if (type.isStruct())
        {
            if (type.payloadSymStruct().isUnion())
                return true;
            for (const SymbolVariable* field : type.payloadSymStruct().fields())
            {
                if (field && typeHasUnionStorageRec(ctx, field->typeRef(), visited))
                    return true;
            }
        }
        return false;
    }

    struct AggregateConstruction
    {
        Sema*                              sema_ = nullptr;
        std::vector<std::byte>             bytes;
        std::vector<DataSegmentRelocation> relocations;
        std::vector<uint8_t>               runtimeBytes;

        void replaceRange(uint64_t offset, uint64_t size)
        {
            SWC_ASSERT(offset <= bytes.size() && size <= bytes.size() - offset);
            // A partial pointer write leaves bytes of the eventual native address.
            // Later writes may replace those bytes too, making the final value constant.
            for (const DataSegmentRelocation& relocation : relocations)
            {
                const uint64_t relocationEnd = uint64_t{relocation.offset} + sizeof(void*);
                if (size && relocation.offset < offset + size && offset < relocationEnd &&
                    (offset > relocation.offset || offset + size < relocationEnd))
                {
                    if (runtimeBytes.empty())
                        runtimeBytes.resize(bytes.size(), 0);
                    std::fill_n(runtimeBytes.data() + relocation.offset, sizeof(void*), 1);
                }
            }
            std::erase_if(relocations, [=](const DataSegmentRelocation& relocation) {
                return size && relocation.offset < offset + size && offset < uint64_t{relocation.offset} + sizeof(void*);
            });
            if (!runtimeBytes.empty())
                std::fill_n(runtimeBytes.data() + offset, size, 0);
        }

        Result writeValue(TypeRef typeRef, ConstantRef valueRef, uint64_t offset)
        {
            Sema&                sema  = *sema_;
            const TypeInfo&      type  = sema.typeMgr().get(typeRef);
            const uint64_t       size  = type.sizeOf(sema.ctx());
            const ConstantValue& value = sema.cstMgr().get(valueRef);
            if (!size)
                return Result::Continue;
            std::span<const std::byte> source;
            DataSegmentRef             sourceRef;
            if ((value.isStruct() || value.isArray()) && value.isPayloadBorrowed())
            {
                source = value.isStruct() ? value.getStruct() : value.getArray();
                if (source.size() != size || !sema.cstMgr().resolveConstantDataSegmentRef(sourceRef, valueRef, source.data()))
                    sourceRef = {};
            }
            if (sourceRef.isInvalid())
            {
                std::vector<std::byte> lowered(size, std::byte{0});
                SWC_RESULT(ConstantLower::lowerToBytes(sema, lowered, valueRef, typeRef));
                // Raw union bytes do not identify which writes established their pointers.
                // Construction sites publish that inventory instead of guessing here.
                if (ConstantHelpers::typeHasUnionStorage(sema.ctx(), typeRef))
                {
                    if (std::ranges::any_of(lowered, [](std::byte valueByte) { return valueByte != std::byte{0}; }))
                        return Result::Error;
                    replaceRange(offset, size);
                    std::fill_n(bytes.data() + offset, size, std::byte{0});
                    return Result::Continue;
                }
                uint32_t     materializedOffset = INVALID_REF;
                DataSegment& segment            = sema.cstMgr().shardDataSegment(0);
                SWC_RESULT(ConstantLower::materializeStaticPayload(materializedOffset, sema, segment, typeRef, lowered));
                sourceRef = {.shardIndex = 0, .offset = materializedOffset};
                source    = {segment.ptr<std::byte>(materializedOffset), static_cast<size_t>(size)};
            }

            replaceRange(offset, size);
            if (size)
                std::memcpy(bytes.data() + offset, source.data(), size);
            std::vector<DataSegmentRelocation> sourceRelocations;
            sema.cstMgr().shardDataSegment(sourceRef.shardIndex).copyRelocations(sourceRelocations, sourceRef.offset, static_cast<uint32_t>(size));
            for (DataSegmentRelocation relocation : sourceRelocations)
            {
                SWC_ASSERT(relocation.offset - sourceRef.offset + sizeof(void*) <= size);
                relocation.offset = static_cast<uint32_t>(offset + relocation.offset - sourceRef.offset);
                if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset && relocation.targetShardIndex == INVALID_REF)
                    relocation.targetShardIndex = sourceRef.shardIndex;
                relocations.push_back(relocation);
            }
            return Result::Continue;
        }

        Result writeDefault(TypeRef typeRef, uint64_t offset)
        {
            Sema&           sema         = *sema_;
            const TypeInfo& declaredType = sema.typeMgr().get(typeRef);
            const uint64_t  size         = declaredType.sizeOf(sema.ctx());
            typeRef                      = declaredType.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
            const TypeInfo& type         = sema.typeMgr().get(typeRef);
            if (!declaredType.isNonNullable() && !type.isNonNullable())
            {
                if (type.isStruct())
                {
                    const SymbolStruct& owner = type.payloadSymStruct();
                    if (owner.attributes().hasRtFlag(RtAttributeFlagsE::Opaque))
                    {
                        // Imported opaque storage does not describe the provider's
                        // runtime initialization, even if a later write covers it.
                        for (const AttributeInstance& attribute : owner.attributes().attributes)
                        {
                            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(sema.ctx()) || attribute.symbol->name(sema.ctx()) != "Opaque")
                                continue;
                            for (const AttributeParamInstance& param : attribute.params)
                            {
                                if (param.nameIdRef == sema.idMgr().addIdentifier("runtimeDefault") && param.valueCstRef.isValid() && sema.cstMgr().get(param.valueCstRef).getBool())
                                    return Result::Error;
                            }
                        }
                    }
                    for (const SymbolVariable* field : owner.fields())
                    {
                        if (!field || SymbolStruct::fieldRequiresExplicitInitialization(sema, *field))
                            continue;
                        const uint64_t fieldOffset = offset + field->offset();
                        if (field->defaultValueRef().isValid())
                            SWC_RESULT(writeValue(field->typeRef(), field->defaultValueRef(), fieldOffset));
                        else
                            SWC_RESULT(writeDefault(field->typeRef(), fieldOffset));
                    }
                    return Result::Continue;
                }
                if (type.isArray())
                {
                    const TypeRef  elementRef  = type.payloadArrayElemTypeRef();
                    const uint64_t elementSize = sema.typeMgr().get(elementRef).sizeOf(sema.ctx());
                    if (elementSize)
                    {
                        for (uint64_t cursor = 0; cursor < size; cursor += elementSize)
                            SWC_RESULT(writeDefault(elementRef, offset + cursor));
                    }
                    return Result::Continue;
                }
            }
            replaceRange(offset, size);
            std::fill_n(bytes.data() + offset, size, std::byte{0});
            return Result::Continue;
        }

        Result collectDynamicRelocations(TypeRef typeRef, uint64_t offset)
        {
            Sema& sema           = *sema_;
            typeRef              = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
            const TypeInfo& type = sema.typeMgr().get(typeRef);
            if (type.isArray())
            {
                const TypeRef  elementRef  = type.payloadArrayElemTypeRef();
                const uint64_t elementSize = sema.typeMgr().get(elementRef).sizeOf(sema.ctx());
                if (elementSize)
                {
                    for (uint64_t cursor = 0; cursor < type.sizeOf(sema.ctx()); cursor += elementSize)
                        SWC_RESULT(collectDynamicRelocations(elementRef, offset + cursor));
                }
            }
            else if (type.isStruct())
            {
                const SymbolStruct& owner = type.payloadSymStruct();
                if (owner.hasOwnDynamicSlot())
                {
                    const uint64_t slotOffset = offset + owner.dynamicSlotOffsets().front();
                    const void*    pointer    = nullptr;
                    std::memcpy(&pointer, bytes.data() + slotOffset, sizeof(pointer));
                    DataSegmentRef target;
                    if (!sema.cstMgr().resolveDataSegmentRef(target, pointer))
                        return Result::Error;
                    replaceRange(slotOffset, sizeof(pointer));
                    relocations.push_back({.offset = static_cast<uint32_t>(slotOffset), .kind = DataSegmentRelocationKind::DataSegmentOffset, .targetOffset = target.offset, .targetShardIndex = target.shardIndex});
                }
                for (const SymbolVariable* field : owner.fields())
                {
                    if (field)
                        SWC_RESULT(collectDynamicRelocations(field->typeRef(), offset + field->offset()));
                }
            }
            return Result::Continue;
        }
    };
}

bool ConstantHelpers::typeHasUnionStorage(const TaskContext& ctx, TypeRef typeRef)
{
    typeRef              = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    const TypeInfo& type = ctx.typeMgr().get(typeRef);
    if (!type.isArray() && !type.isStruct())
        return false;
    std::unordered_set<TypeRef> visited;
    return typeHasUnionStorageRec(ctx, typeRef, visited);
}

ConstantRef ConstantHelpers::materializeAggregateConstructionConstant(Sema& sema, TypeRef typeRef, std::span<const ConstantPayloadWrite> writes)
{
    const TypeInfo& type = sema.typeMgr().get(typeRef);
    const uint64_t  size = type.sizeOf(sema.ctx());
    SWC_ASSERT(size <= UINT32_MAX);
    AggregateConstruction construction{.sema_ = &sema, .bytes = std::vector<std::byte>(size, std::byte{0})};
    if (construction.writeDefault(typeRef, 0) != Result::Continue)
        return ConstantRef::invalid();
    for (const ConstantPayloadWrite& write : writes)
    {
        if (write.valueRef.isValid() && construction.writeValue(write.typeRef, write.valueRef, write.offset) != Result::Continue)
            return ConstantRef::invalid();
    }
    if (SymbolStruct::initializeDynamicIdentityBytes(sema, construction.bytes, typeRef) != Result::Continue)
        return ConstantRef::invalid();
    if (construction.collectDynamicRelocations(typeRef, 0) != Result::Continue)
        return ConstantRef::invalid();
    if (std::ranges::any_of(construction.runtimeBytes, [](uint8_t byte) { return byte != 0; }))
        return ConstantRef::invalid();

    const uint32_t shardIndex    = staticPayloadPlacementShardIndex(sema.ctx(), typeRef, construction.bytes, false, 0);
    DataSegment&   segment       = sema.cstMgr().shardDataSegment(shardIndex);
    const auto [offset, storage] = segment.reserveBytes(static_cast<uint32_t>(size), type.alignOf(sema.ctx()), false);
    if (size)
        std::memcpy(storage, construction.bytes.data(), size);
    for (const DataSegmentRelocation& relocation : construction.relocations)
    {
        if (relocation.kind == DataSegmentRelocationKind::FunctionSymbol)
            segment.addFunctionRelocation(offset + relocation.offset, relocation.targetSymbol, relocation.allowUnresolvedFunction);
        else
            segment.addRelocation(offset + relocation.offset, {.shardIndex = relocation.targetShardIndex, .offset = relocation.targetOffset});
    }
    const ConstantValue result = makeMaterializedConstantValue(sema, typeRef, {storage, static_cast<size_t>(size)}, {.shardIndex = shardIndex, .offset = offset});
    // Equal union bytes can carry different relocation inventories (an integer view
    // versus a pointer view). Byte-only constant interning cannot merge those facts.
    return sema.cstMgr().addUniqueMaterializedPayloadConstant(result);
}

bool ConstantHelpers::hasSourceFunctionRelocation(Sema& sema, const void* fieldPtr)
{
    DataSegmentRef sourceRef;
    if (!sema.cstMgr().resolveDataSegmentRef(sourceRef, fieldPtr))
        return false;

    DataSegmentRelocation relocation;
    return sema.cstMgr().shardDataSegment(sourceRef.shardIndex).findRelocation(relocation, sourceRef.offset, DataSegmentRelocationKind::FunctionSymbol);
}

Result ConstantHelpers::waitStaticPayloadTypeReady(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef)
{
    std::unordered_set<TypeRef> visited;
    return waitStaticPayloadTypeReadyRec(sema, typeRef, waitNodeRef, visited);
}

uint64_t ConstantHelpers::materializeConstantStorageAndGetAddress(Sema& sema, const SemaNodeView& view)
{
    SWC_ASSERT(view.type());
    TypeRef storageTypeRef = ConstantHelpers::constantFoldStorageTypeRef(sema, view.typeRef());
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

    ConstantManager&     manager   = sema.cstMgr();
    const DataSegmentRef cachedRef = manager.findConstantStorage(view.cstRef(), storageTypeRef);
    if (cachedRef.isValid())
        return reinterpret_cast<uint64_t>(manager.shardDataSegment(cachedRef.shardIndex).ptr<std::byte>(cachedRef.offset));

    SmallVector<std::byte> storage(sizeOf);
    const std::span        storageSpan{storage.data(), storage.size()};
    SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, storageSpan, view.cstRef(), storageTypeRef) == Result::Continue);

    // Preserve alignment and register embedded pointer relocations. Interning raw
    // bytes would leave compiler-process addresses in the native executable.
    const uint32_t shardIndex = view.cstRef().get() >> ConstantManager::LOCAL_BITS;
    DataSegment&   segment    = manager.shardDataSegment(shardIndex);
    uint32_t       offset     = INVALID_REF;
    SWC_INTERNAL_CHECK(ConstantLower::materializeStaticPayload(offset, sema, segment, storageTypeRef, storageSpan) == Result::Continue);
    const DataSegmentRef dataRef = manager.publishConstantStorage(view.cstRef(), storageTypeRef, {.shardIndex = shardIndex, .offset = offset});
    return reinterpret_cast<uint64_t>(manager.shardDataSegment(dataRef.shardIndex).ptr<std::byte>(dataRef.offset));
}

uint32_t ConstantHelpers::staticPayloadPlacementShardIndex(const TaskContext& ctx, TypeRef typeRef, std::span<const std::byte> payload, bool hasRequiredShard, uint32_t requiredShard)
{
    // A pointer relocation pins the payload to a specific shard; honor it.
    if (hasRequiredShard)
        return requiredShard;

    // Otherwise a pointer-free payload may live in any shard. Historically these all funnelled into
    // shard 0, serializing every static-payload materialization (from BOTH ConstantHelpers and
    // CodeGenConstantHelpers) on that one data-segment mutex — the dominant contention point. We spread
    // them, but the placement shard cannot be arbitrary: the same logical constant can also be produced
    // by ConstantManager::addConstantSlow (a non-borrowed value), which lands in shard
    // `Math::hash(value.hash()) & mask`. Interning only deduplicates within a shard, so to keep every
    // path rendezvousing on a single constant (and a single address, which pointer identity relies on),
    // the placement shard must match that exact key. We compute the hash of the borrowed struct/array
    // ConstantValue that makeMaterializedConstantValue will produce, and derive the shard the same way.
    //
    // Scalars/enums fall through to shard 0: those produce non-span constants routed through a different
    // add path, so we leave their legacy placement untouched.
    const TypeInfo& originalType = ctx.typeMgr().get(typeRef);

    if (ConstantHelpers::isEnumValueType(ctx, originalType, typeRef))
        return 0;

    const TypeRef   storageTypeRef = originalType.isAlias() || originalType.isEnum() ? originalType.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum) : typeRef;
    const TypeInfo& storageType    = storageTypeRef == typeRef ? originalType : ctx.typeMgr().get(storageTypeRef);

    // Mirror makeMaterializedConstantValue's kind decision. Only the array/struct branches build a
    // borrowed span constant; the scalar branch takes a different code path.
    ConstantKind kind;
    if (storageType.isArray() || storageType.isSimd())
        kind = ConstantKind::Array;
    else if (storageType.isBool() || storageType.isChar() || storageType.isRune() || storageType.isInt() || storageType.isFloat() || storageType.isAnyPointer() || storageType.isReference() || storageType.isTypeInfo() || storageType.isCString() || (storageType.isFunction() && !storageType.isLambdaClosure()))
        return 0;
    else
        kind = ConstantKind::Struct;

    // Replicate ConstantValue::hash for the produced (borrowed) value: its final typeRef is the original
    // typeRef and its payload bytes are these bytes.
    uint32_t valueHash = Math::hash(static_cast<uint32_t>(kind));
    valueHash          = Math::hashCombine(valueHash, typeRef.get());
    valueHash          = Math::hashCombine(valueHash, Math::hash(payload));

    return Math::hash(valueHash) & (ConstantManager::SHARD_COUNT - 1);
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

    const TypeRef   storageTypeRef = typeInfo.isAlias() || typeInfo.isEnum() ? typeInfo.unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum) : typeRef;
    const TypeInfo& storageType    = storageTypeRef == typeRef ? typeInfo : ctx.typeMgr().get(storageTypeRef);
    if (storageType.isStruct() && storageType.payloadSymStruct().isUnion())
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeRef, payload));

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(shardIndex, hasRequiredShard, sema, typeRef, payload))
        return ConstantRef::invalid();

    const uint32_t placementShardIndex = staticPayloadPlacementShardIndex(ctx, typeRef, payload, hasRequiredShard, shardIndex);
    DataSegment&   segment             = sema.cstMgr().shardDataSegment(placementShardIndex);
    uint32_t       offset              = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(offset, sema, segment, typeRef, payload) != Result::Continue)
        return ConstantRef::invalid();

    SWC_ASSERT(sizeOf != 0 || offset == INVALID_REF);
    const DataSegmentRef             dataRef{.shardIndex = placementShardIndex, .offset = offset};
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
    if (!storage || offset == INVALID_REF)
        return Result::Error;

    const uint32_t fileNameLength = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, fileName.ptr), fileName);

    uint32_t funcNameLength = 0;
    if (funcName.empty())
    {
        auto* rtLoc = segment.ptr<Runtime::SourceCodeLocation>(offset);
        if (!rtLoc)
            return Result::Error;
        rtLoc->funcName.ptr = nullptr;
    }
    else
    {
        funcNameLength = segment.addString(offset, offsetof(Runtime::SourceCodeLocation, funcName.ptr), funcName);
    }

    auto* rtLoc = segment.ptr<Runtime::SourceCodeLocation>(offset);
    if (!rtLoc)
        return Result::Error;
    rtLoc->fileName.length = fileNameLength;
    rtLoc->funcName.length = funcNameLength;
    rtLoc->lineStart       = codeRange.line;
    rtLoc->colStart        = codeRange.column;
    rtLoc->lineEnd         = codeRange.line;
    rtLoc->colEnd          = codeRange.column + codeRange.len;

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
