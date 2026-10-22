#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantEnumType.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/PointerSet.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct FunctionNameScratch
    {
        Utf8* value = nullptr;

        ~FunctionNameScratch()
        {
            if (value && value->capacity() > MAX_RETAINED_CAPACITY)
                Utf8{}.swap(*value);
        }

        static constexpr size_t MAX_RETAINED_CAPACITY = 256;
    };

    Result waitStaticPayloadTypeReadyRec(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, WalkPath<TypeRef>& visited);

    Result waitStaticPayloadTypeReadyRecImpl(Sema& sema, const TypeInfo& typeInfo, AstNodeRef waitNodeRef, WalkPath<TypeRef>& visited)
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

        if (typeInfo.isAggregate())
        {
            for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
                SWC_RESULT(waitStaticPayloadTypeReadyRec(sema, fieldTypeRef, waitNodeRef, visited));
        }

        return Result::Continue;
    }

    Result waitStaticPayloadTypeReadyRec(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, WalkPath<TypeRef>& visited)
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

        if (!visited.insert(typeRef))
            return Result::Continue;

        const Result result = waitStaticPayloadTypeReadyRecImpl(sema, typeInfo, waitNodeRef, visited);
        visited.erase(typeRef);
        return result;
    }

    ConstantValue makeMaterializedConstantValue(TaskContext& ctx, const TypeInfo& originalType, const TypeInfo& storageType, std::span<const std::byte> storedBytes, DataSegmentRef dataSegmentRef)
    {
        const TypeRef typeRef        = originalType.typeRef();
        const TypeRef storageTypeRef = storageType.typeRef();
        ConstantValue result;

        if (storageType.isStruct() || storageType.isAny() || storageType.isInterface() || storageType.isAggregate() || (storageType.isFunction() && storageType.isLambdaClosure()))
            result = ConstantValue::makeStructBorrowed(ctx, storageTypeRef, storedBytes);
        else if (storageType.isArrayOrSimd())
            result = ConstantValue::makeArrayBorrowed(ctx, storageTypeRef, storedBytes);
        else
            result = ConstantValue::make(ctx, storedBytes.data(), storageTypeRef, ConstantValue::PayloadOwnership::Borrowed);

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

    bool requirePointerShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, const void* ptr)
    {
        if (!ptr)
            return true;

        DataSegmentRef ref;
        if (!sema.cstMgr().resolveDataSegmentRef(ref, ptr))
            return false;

        if (!hasRequiredShard)
        {
            outShardIndex    = ref.shardIndex;
            hasRequiredShard = true;
        }

        // Cross-shard payload relocations make this a placement preference for the allocation.
        return true;
    }

    bool resolveClosureStaticPayloadRequiredShardIndex(uint32_t& outShardIndex, bool& hasRequiredShard, Sema& sema, std::span<const std::byte> payload)
    {
        SWC_ASSERT(payload.size() == sizeof(Runtime::ClosureValue));

        const auto* runtimeClosure = reinterpret_cast<const Runtime::ClosureValue*>(payload.data());
        if (!requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeClosure->invoke))
            return false;

        const auto capturedTarget = reinterpret_cast<const void*>(*reinterpret_cast<const uint64_t*>(runtimeClosure->capture));
        return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, capturedTarget);
    }

    bool typeHasUnionStorageRec(const TaskContext& ctx, const TypeInfo& declaredType, RefSet<TypeRef>& visited)
    {
        const TypeInfo* type = &declaredType.unwrapAliasEnumTypeOrSelf(ctx);
        if (!type->isArray() && !type->isStruct())
            return false;

        if (!visited.insert(type->typeRef()))
            return false;
        if (type->isArray())
            return typeHasUnionStorageRec(ctx, ctx.typeMgr().get(type->payloadArrayElemTypeRef()), visited);

        if (type->isStruct())
        {
            if (type->payloadSymStruct().isUnion())
                return true;

            for (const SymbolVariable* field : type->payloadSymStruct().fields())
            {
                if (field && typeHasUnionStorageRec(ctx, ctx.typeMgr().get(field->typeRef()), visited))
                    return true;
            }
        }

        return false;
    }

    struct AggregateConstruction
    {
        Sema* sema_ = nullptr;

        std::vector<std::byte>             bytes;
        std::vector<DataSegmentRelocation> relocations;
        std::vector<uint8_t>               runtimeBytes;

        void replaceRange(uint64_t offset, uint64_t size)
        {
            SWC_ASSERT(offset <= bytes.size() && size <= bytes.size() - offset);

            // A partial pointer write leaves bytes of the eventual native address.
            // Later writes may replace those bytes too, making the final value constant.
            std::erase_if(relocations, [=, this](const DataSegmentRelocation& relocation) {
                const uint64_t relocationEnd = uint64_t{relocation.offset} + sizeof(void*);
                if (!size || relocation.offset >= offset + size || offset >= relocationEnd)
                    return false;

                if (offset > relocation.offset || offset + size < relocationEnd)
                {
                    if (runtimeBytes.empty())
                        runtimeBytes.resize(bytes.size(), 0);
                    std::fill_n(runtimeBytes.data() + relocation.offset, sizeof(void*), 1);
                }

                return true;
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
            if (value.isStructOrArray() && value.isPayloadBorrowed())
            {
                source = value.isStruct() ? value.getStruct() : value.getArray();
                if (source.size() != size || !sema.cstMgr().resolveConstantDataSegmentRef(sourceRef, valueRef, source.data()))
                    sourceRef = {};
            }

            if (sourceRef.isInvalid())
            {
                std::vector<std::byte> lowered(size, std::byte{0});
                SWC_RESULT(ConstantLower::lowerToBytes(sema, lowered, valueRef, type));

                // Raw union bytes do not identify which writes established their pointers.
                // Construction sites publish that inventory instead of guessing here.
                if (ConstantHelpers::typeHasUnionStorage(sema.ctx(), type))
                {
                    if (std::ranges::any_of(lowered, [](std::byte valueByte) { return valueByte != std::byte{0}; }))
                        return Result::Error;

                    replaceRange(offset, size);
                    std::fill_n(bytes.data() + offset, size, std::byte{0});
                    return Result::Continue;
                }

                uint32_t     materializedOffset = INVALID_REF;
                DataSegment& segment            = sema.cstMgr().shardDataSegment(0);
                SWC_RESULT(ConstantLower::materializeStaticPayload(sema, materializedOffset, segment, type, lowered));

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

        Result writeDefault(const TypeInfo& declaredType, uint64_t size, uint64_t offset)
        {
            Sema&           sema = *sema_;
            const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(sema.ctx());
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
                        {
                            const TypeInfo& fieldType = sema.typeMgr().get(field->typeRef());
                            SWC_RESULT(writeDefault(fieldType, fieldType.sizeOf(sema.ctx()), fieldOffset));
                        }
                    }

                    return Result::Continue;
                }

                if (type.isArray())
                {
                    const TypeInfo& elementType = sema.typeMgr().get(type.payloadArrayElemTypeRef());
                    const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
                    if (elementSize)
                    {
                        for (uint64_t cursor = 0; cursor < size; cursor += elementSize)
                            SWC_RESULT(writeDefault(elementType, elementSize, offset + cursor));
                    }

                    return Result::Continue;
                }
            }

            replaceRange(offset, size);
            std::fill_n(bytes.data() + offset, size, std::byte{0});
            return Result::Continue;
        }

        Result collectDynamicRelocations(const TypeInfo& declaredType, uint64_t offset)
        {
            Sema&           sema = *sema_;
            const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(sema.ctx());
            if (type.isArray())
            {
                const TypeInfo& elementType = sema.typeMgr().get(type.payloadArrayElemTypeRef());
                const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
                if (elementSize)
                {
                    const uint64_t size = type.sizeOf(sema.ctx());
                    for (uint64_t cursor = 0; cursor < size; cursor += elementSize)
                        SWC_RESULT(collectDynamicRelocations(elementType, offset + cursor));
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
                        SWC_RESULT(collectDynamicRelocations(sema.typeMgr().get(field->typeRef()), offset + field->offset()));
                }
            }

            return Result::Continue;
        }
    };
}

bool ConstantHelpers::typeHasUnionStorage(const TaskContext& ctx, const TypeInfo& declaredType)
{
    const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(ctx);
    if (!type.isArray() && !type.isStruct())
        return false;

    RefSet<TypeRef> visited;
    return typeHasUnionStorageRec(ctx, type, visited);
}

ConstantRef ConstantHelpers::materializeAggregateConstructionConstant(Sema& sema, TypeRef typeRef, std::span<const ConstantPayloadWrite> writes)
{
    const TypeInfo& type = sema.typeMgr().get(typeRef);
    const uint64_t  size = type.sizeOf(sema.ctx());
    SWC_ASSERT(size <= UINT32_MAX);

    AggregateConstruction construction{.sema_ = &sema, .bytes = std::vector<std::byte>(size, std::byte{0})};
    if (construction.writeDefault(type, size, 0) != Result::Continue)
        return ConstantRef::invalid();

    for (const ConstantPayloadWrite& write : writes)
    {
        if (write.valueRef.isValid() && construction.writeValue(write.typeRef, write.valueRef, write.offset) != Result::Continue)
            return ConstantRef::invalid();
    }

    if (SymbolStruct::initializeDynamicIdentityBytes(sema, construction.bytes, type) != Result::Continue)
        return ConstantRef::invalid();
    if (construction.collectDynamicRelocations(type, 0) != Result::Continue)
        return ConstantRef::invalid();
    if (std::ranges::any_of(construction.runtimeBytes, [](uint8_t byte) { return byte != 0; }))
        return ConstantRef::invalid();

    const TypeInfo& storageType = type.unwrapAliasEnumTypeOrSelf(sema.ctx());

    const uint32_t shardIndex    = staticPayloadPlacementShardIndex(sema.ctx(), type, storageType, construction.bytes, false, 0);
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

    const ConstantValue result = makeMaterializedConstantValue(sema.ctx(), type, storageType, {storage, static_cast<size_t>(size)}, {.shardIndex = shardIndex, .offset = offset});

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
    WalkPath<TypeRef> visited;
    return waitStaticPayloadTypeReadyRec(sema, typeRef, waitNodeRef, visited);
}

uint64_t ConstantHelpers::materializeConstantStorageAndGetAddress(Sema& sema, const SemaNodeView& view)
{
    SWC_ASSERT(view.type());
    const TypeInfo& originalStorageType = SemaHelpers::aliasEnumType(sema, view);
    TypeRef         storageTypeRef      = originalStorageType.typeRef();
    if (view.cstRef().isValid())
    {
        if (originalStorageType.isScalarUnsized())
        {
            ConstantRef concretizedCstRef = ConstantRef::invalid();
            SWC_INTERNAL_CHECK(Cast::concretizeConstant(sema, concretizedCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unknown) == Result::Continue);
            if (concretizedCstRef.isValid())
                storageTypeRef = sema.cstMgr().get(concretizedCstRef).typeRef();
        }

        storageTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, storageTypeRef, view.cstRef());
    }

    const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
    const uint64_t  sizeOf      = storageType.sizeOf(sema.ctx());
    if (!sizeOf)
        return 0;

    ConstantManager&     manager   = sema.cstMgr();
    const DataSegmentRef cachedRef = manager.findConstantStorage(view.cstRef(), storageTypeRef);
    if (cachedRef.isValid())
        return reinterpret_cast<uint64_t>(manager.shardDataSegment(cachedRef.shardIndex).ptr<std::byte>(cachedRef.offset));

    SmallVector<std::byte> storage(sizeOf);
    const std::span        storageSpan{storage.data(), storage.size()};
    SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, storageSpan, view.cstRef(), storageType) == Result::Continue);

    // Preserve alignment and register embedded pointer relocations. Interning raw
    // bytes would leave compiler-process addresses in the native executable.
    const uint32_t shardIndex = view.cstRef().get() >> ConstantStorageLayout::LOCAL_BITS;
    DataSegment&   segment    = manager.shardDataSegment(shardIndex);
    uint32_t       offset     = INVALID_REF;
    SWC_INTERNAL_CHECK(ConstantLower::materializeStaticPayload(sema, offset, segment, storageType, storageSpan) == Result::Continue);

    const DataSegmentRef dataRef = manager.publishConstantStorage(view.cstRef(), storageTypeRef, {.shardIndex = shardIndex, .offset = offset});
    return reinterpret_cast<uint64_t>(manager.shardDataSegment(dataRef.shardIndex).ptr<std::byte>(dataRef.offset));
}

uint32_t ConstantHelpers::staticPayloadPlacementShardIndex(const TaskContext& ctx, const TypeInfo& originalType, const TypeInfo& storageType, std::span<const std::byte> payload, bool hasRequiredShard, uint32_t requiredShard)
{
    // A pointer relocation pins the payload to a specific shard; honor it.
    if (hasRequiredShard)
        return requiredShard;

    // Distribute pointer-free payloads to avoid serializing shard 0. Placement must
    // match addConstantSlow's Math::hash(value.hash()) & mask: interning deduplicates
    // only within a shard, and pointer identity requires one canonical address. Hash
    // the borrowed struct/array value produced by makeMaterializedConstantValue.
    // Scalars/enums keep shard 0 because their non-span constants use another path.
    const TypeRef typeRef = originalType.typeRef();

    if (ConstantHelpers::isEnumValueType(ctx, originalType, typeRef))
        return 0;

    // Mirror makeMaterializedConstantValue: only struct/array kinds use borrowed spans.
    ConstantKind kind;
    if (storageType.isArrayOrSimd())
        kind = ConstantKind::Array;
    else if (storageType.isNumericIntLike() || storageType.isFloat() || storageType.isPointerOrReference() || storageType.isTypeInfo() || storageType.isCString() || (storageType.isFunction() && !storageType.isLambdaClosure()))
        return 0;
    else
        kind = ConstantKind::Struct;

    // Match ConstantValue::hash using the original declared type and these payload bytes.
    uint32_t valueHash = Math::hash(static_cast<uint32_t>(kind));
    valueHash          = Math::hashCombine(valueHash, typeRef.get());
    valueHash          = Math::hashCombine(valueHash, Math::hash(payload));

    return Math::hash(valueHash) & (ConstantStorageLayout::SHARD_COUNT - 1);
}

bool ConstantHelpers::resolveStaticPayloadRequiredShardIndex(Sema& sema, uint32_t& outShardIndex, bool& hasRequiredShard, const TypeInfo& typeInfo, std::span<const std::byte> payload)
{
    TaskContext&       ctx     = sema.ctx();
    const TypeManager& typeMgr = ctx.typeMgr();

    // The entry validates size; recursive spans use the resolved child type's size.
    // Aliases, enum wrappers and type values preserve their underlying layout.
    SWC_ASSERT(typeInfo.sizeOf(ctx) == payload.size());
    if (typeInfo.isAlias())
    {
        const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, typeInfo.typeRef(), TypeExpandE::Alias);
        return unwrappedTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, typeMgr.get(unwrappedTypeRef), payload);
    }

    if (typeInfo.isTypeValue())
    {
        const TypeRef valueTypeRef = typeInfo.payloadTypeRef();
        return valueTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, typeMgr.get(valueTypeRef), payload);
    }

    if (typeInfo.isEnum())
    {
        const TypeRef underlyingTypeRef = typeInfo.payloadSymEnum().underlyingTypeRef();
        return underlyingTypeRef.isValid() && resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, typeMgr.get(underlyingTypeRef), payload);
    }

    if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
        return resolveClosureStaticPayloadRequiredShardIndex(outShardIndex, hasRequiredShard, sema, payload);

    if (typeInfo.isNumericIntLike() || typeInfo.isFloat() || typeInfo.isString() || typeInfo.isSimd())
        return true;

    if (typeInfo.isSlice())
    {
        SWC_ASSERT(payload.size() == sizeof(Runtime::Slice<std::byte>));

        // Empty slices need no element layout. Their type can exist before element
        // size is computed, so do not inspect that size until the count is nonzero.
        const auto* runtimeSlice = reinterpret_cast<const Runtime::Slice<std::byte>*>(payload.data());
        if (runtimeSlice->count == 0)
            return true;

        const TypeRef   elementTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo& elementType    = typeMgr.get(elementTypeRef);
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
            if (!resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, elementType, elementBytes))
                return false;
        }

        return true;
    }

    if (typeInfo.isAny())
    {
        SWC_ASSERT(payload.size() == sizeof(Runtime::Any));

        const auto* runtimeAny = reinterpret_cast<const Runtime::Any*>(payload.data());
        if (!runtimeAny->type)
            return runtimeAny->value == nullptr;

        return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeAny->type);
    }

    if (typeInfo.isInterface())
    {
        SWC_ASSERT(payload.size() == sizeof(Runtime::Interface));

        const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(payload.data());
        return requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->obj) &&
               requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, runtimeInterface->itable);
    }

    if (typeInfo.isArray())
    {
        const TypeRef   elementTypeRef = typeInfo.payloadArrayElemTypeRef();
        const TypeInfo& elementType    = typeMgr.get(elementTypeRef);
        const uint64_t  elementSize    = elementType.sizeOf(ctx);
        if (!elementSize)
            return payload.empty();

        uint64_t totalCount = typeInfo.arrayTotalElementCount();

        for (uint64_t idx = 0; idx < totalCount; ++idx)
        {
            const uint64_t elementOffset = idx * elementSize;
            const auto     elementBytes  = std::span{payload.data() + elementOffset, static_cast<size_t>(elementSize)};
            if (!resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, elementType, elementBytes))
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
            if (!resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, fieldType, fieldBytes))
                return false;
        }

        return true;
    }

    if (typeInfo.isAggregate())
    {
        uint64_t offset = 0;
        for (const TypeRef fieldTypeRef : typeInfo.payloadAggregate().types)
        {
            const TypeInfo& fieldType = typeMgr.get(fieldTypeRef);
            const uint64_t  fieldSize = fieldType.sizeOf(ctx);
            if (!fieldSize)
                continue;

            uint32_t align = fieldType.alignOf(ctx);
            if (!align)
                align = 1;

            offset = Math::alignUpU64(offset, align);
            if (offset + fieldSize > payload.size())
                return false;

            const auto fieldBytes = std::span{payload.data() + offset, static_cast<size_t>(fieldSize)};
            if (!resolveStaticPayloadRequiredShardIndex(sema, outShardIndex, hasRequiredShard, fieldType, fieldBytes))
                return false;

            offset += fieldSize;
        }

        return true;
    }

    if (typeInfo.isPointerLikeOrReference())
    {
        SWC_ASSERT(payload.size() == sizeof(uint64_t));

        const uint64_t rawPtr = *reinterpret_cast<const uint64_t*>(payload.data());
        if (requirePointerShardIndex(outShardIndex, hasRequiredShard, sema, reinterpret_cast<const void*>(rawPtr)))
            return true;

        return hasSourceFunctionRelocation(sema, payload.data());
    }

    return false;
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

    const TypeInfo& storageType = typeInfo.unwrapAliasEnumTypeOrSelf(ctx);
    if (storageType.isStruct() && storageType.payloadSymStruct().isUnion())
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeStruct(ctx, typeRef, payload));

    uint32_t shardIndex       = 0;
    bool     hasRequiredShard = false;
    if (!resolveStaticPayloadRequiredShardIndex(sema, shardIndex, hasRequiredShard, typeInfo, payload))
        return ConstantRef::invalid();

    const uint32_t placementShardIndex = staticPayloadPlacementShardIndex(ctx, typeInfo, storageType, payload, hasRequiredShard, shardIndex);
    DataSegment&   segment             = sema.cstMgr().shardDataSegment(placementShardIndex);
    uint32_t       offset              = INVALID_REF;
    if (ConstantLower::materializeStaticPayload(sema, offset, segment, typeInfo, payload) != Result::Continue)
        return ConstantRef::invalid();

    SWC_ASSERT(sizeOf != 0 || offset == INVALID_REF);
    const DataSegmentRef             dataRef{.shardIndex = placementShardIndex, .offset = offset};
    const std::span<const std::byte> storedBytes = sizeOf ? std::span{segment.ptr<std::byte>(offset), sizeOf} : std::span<const std::byte>{};

    const ConstantValue result = makeMaterializedConstantValue(ctx, typeInfo, storageType, storedBytes, dataRef);
    if (!result.isValid())
        return ConstantRef::invalid();

    if (dataRef.isValid() && result.isSpanPayload() && result.isPayloadBorrowed())
        return sema.cstMgr().addMaterializedPayloadConstant(result);

    return sema.cstMgr().addConstant(ctx, result);
}

Result ConstantHelpers::makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const SourceCodeRange& codeRange, const SymbolFunction* function)
{
    outCstRef = ConstantRef::invalid();

    const TaskContext& ctx     = sema.ctx();
    TypeRef            typeRef = TypeRef::invalid();
    SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, SourceCodeRef::invalid()));

    const SourceView*      srcView  = codeRange.srcView;
    const SourceFile*      file     = srcView ? srcView->file() : nullptr;
    const std::string_view fileName = file ? std::string_view{file->pathString()} : std::string_view{""};

    std::string_view    funcName{""};
    FunctionNameScratch functionNameScratch;
    if (function)
    {
        thread_local Utf8 funcNameStorage;
        funcNameStorage.clear();
        functionNameScratch.value = &funcNameStorage;
        function->appendFullScopedName(ctx, funcNameStorage);
        funcName = funcNameStorage;
    }

    const Runtime::SourceCodeLocation location{
        .fileName  = {.ptr = fileName.data(), .length = fileName.size()},
        .funcName  = {.ptr = funcName.data(), .length = funcName.size()},
        .lineStart = codeRange.line,
        .colStart  = codeRange.column,
        .lineEnd   = codeRange.line,
        .colEnd    = codeRange.column + codeRange.len,
    };

    outCstRef = sema.cstMgr().addSourceCodeLocation(ctx, typeRef, location);
    return Result::Continue;
}

Result ConstantHelpers::makeSourceCodeLocation(Sema& sema, ConstantRef& outCstRef, const AstNode& node, const SymbolFunction* function)
{
    const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
    return makeSourceCodeLocation(sema, outCstRef, codeRange, function);
}

SWC_END_NAMESPACE();
