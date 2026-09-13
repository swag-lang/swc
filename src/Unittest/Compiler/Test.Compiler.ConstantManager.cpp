#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHeap.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ConstantManager_CopiesBorrowedStructPayloadOutsideDataSegment)
{
    Runtime::String runtimeString{
        .ptr    = "borrowed-struct",
        .length = 15,
    };
    const char*    expectedPtr    = runtimeString.ptr;
    const uint64_t expectedLength = runtimeString.length;

    const ConstantValue  value  = ConstantValue::makeStructBorrowed(ctx, ctx.typeMgr().typeString(), std::span{reinterpret_cast<const std::byte*>(&runtimeString), sizeof(runtimeString)});
    const ConstantRef    cstRef = ctx.cstMgr().addConstant(ctx, value);
    const ConstantValue& stored = ctx.cstMgr().get(cstRef);
    if (!stored.isStruct() || stored.typeRef() != ctx.typeMgr().typeString())
        return Result::Error;

    DataSegmentRef storedRef;
    if (!ctx.cstMgr().resolveConstantDataSegmentRef(storedRef, cstRef, stored.getStruct().data()))
        return Result::Error;
    if (stored.getStruct().data() == reinterpret_cast<const std::byte*>(&runtimeString))
        return Result::Error;

    runtimeString.ptr    = nullptr;
    runtimeString.length = 0;

    const auto* storedString = stored.getStruct<Runtime::String>(ctx.typeMgr().typeString());
    if (!storedString)
        return Result::Error;
    if (storedString->ptr != expectedPtr || storedString->length != expectedLength)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_StoresNullableCStringFromBlockPointer)
{
    const TypeRef nullableCStringTypeRef = ctx.typeMgr().addType(TypeInfo::makeCString(TypeInfoFlagsE::Nullable));

    ConstantValue value = ConstantValue::makeBlockPointer(ctx, ctx.typeMgr().typeU8(), 0x1234, TypeInfoFlagsE::Const);
    value.setTypeRef(nullableCStringTypeRef);

    const ConstantRef    cstRef = ctx.cstMgr().addConstant(ctx, value);
    const ConstantValue& stored = ctx.cstMgr().get(cstRef);
    if (!stored.isBlockPointer() || stored.typeRef() != nullableCStringTypeRef)
        return Result::Error;

    if (stored.getBlockPointer() != 0x1234)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantValue_MakesNullableCStringFromRuntimePointer)
{
    const TypeRef nullableCStringTypeRef = ctx.typeMgr().addType(TypeInfo::makeCString(TypeInfoFlagsE::Nullable));

    constexpr uint64_t rawPtr = 0x1234;
    ConstantValue      value  = ConstantValue::make(ctx, &rawPtr, nullableCStringTypeRef);
    if (!value.isBlockPointer() || value.typeRef() != nullableCStringTypeRef)
        return Result::Error;

    if (value.getBlockPointer() != rawPtr)
        return Result::Error;

    constexpr uint64_t nullPtr = 0;
    value                      = ConstantValue::make(ctx, &nullPtr, nullableCStringTypeRef);
    if (!value.isNull() || value.typeRef() != nullableCStringTypeRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_CopiesBorrowedArrayPayloadOutsideDataSegment)
{
    std::array source{
        std::byte{0x10},
        std::byte{0x20},
        std::byte{0x30},
        std::byte{0x40},
    };
    const auto expectedBytes = source;

    std::array           dims{source.size()};
    const TypeRef        arrayTypeRef = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));
    const ConstantValue  value        = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{source.data(), source.size()});
    const ConstantRef    cstRef       = ctx.cstMgr().addConstant(ctx, value);
    const ConstantValue& stored       = ctx.cstMgr().get(cstRef);
    if (!stored.isArray() || stored.typeRef() != arrayTypeRef)
        return Result::Error;

    DataSegmentRef storedRef;
    if (!ctx.cstMgr().resolveConstantDataSegmentRef(storedRef, cstRef, stored.getArray().data()))
        return Result::Error;
    if (stored.getArray().data() == source.data())
        return Result::Error;

    source.fill(std::byte{0});
    if (!std::ranges::equal(stored.getArray(), std::span{expectedBytes.data(), expectedBytes.size()}))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_DeduplicatesBorrowedArrayPayloadsByValue)
{
    std::array first{
        std::byte{0x10},
        std::byte{0x20},
        std::byte{0x30},
        std::byte{0x40},
    };
    const auto second = first;

    std::array    dims{first.size()};
    const TypeRef arrayTypeRef = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));

    const ConstantRef firstRef  = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{first.data(), first.size()}));
    const ConstantRef secondRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{second.data(), second.size()}));
    if (firstRef != secondRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_CachesZeroPayloadConstantsByType)
{
    const TypeRef     stringTypeRef   = ctx.typeMgr().typeString();
    const ConstantRef firstStringRef  = ctx.cstMgr().addZeroPayloadConstant(ctx, stringTypeRef);
    const ConstantRef secondStringRef = ctx.cstMgr().addZeroPayloadConstant(ctx, stringTypeRef);
    if (!firstStringRef.isValid() || firstStringRef != secondStringRef)
        return Result::Error;

    const ConstantValue& stringValue = ctx.cstMgr().get(firstStringRef);
    if (!stringValue.isStruct() || stringValue.typeRef() != stringTypeRef)
        return Result::Error;
    for (const std::byte byte : stringValue.getStruct())
    {
        if (byte != std::byte{0})
            return Result::Error;
    }

    std::array        dims{4ULL};
    const TypeRef     arrayTypeRef   = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));
    const ConstantRef firstArrayRef  = ctx.cstMgr().addZeroPayloadConstant(ctx, arrayTypeRef);
    const ConstantRef secondArrayRef = ctx.cstMgr().addZeroPayloadConstant(ctx, arrayTypeRef);
    if (!firstArrayRef.isValid() || firstArrayRef != secondArrayRef || firstArrayRef == firstStringRef)
        return Result::Error;

    const ConstantValue& arrayValue = ctx.cstMgr().get(firstArrayRef);
    if (!arrayValue.isArray() || arrayValue.typeRef() != arrayTypeRef)
        return Result::Error;
    for (const std::byte byte : arrayValue.getArray())
    {
        if (byte != std::byte{0})
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_CopiesBorrowedSlicePayloadOutsideDataSegment)
{
    std::array source{
        std::byte{0xAA},
        std::byte{0xBB},
        std::byte{0xCC},
    };
    const auto expectedBytes = source;

    const ConstantValue  value  = ConstantValue::makeSliceBorrowed(ctx, ctx.typeMgr().typeU8(), std::span{source.data(), source.size()});
    const ConstantRef    cstRef = ctx.cstMgr().addConstant(ctx, value);
    const ConstantValue& stored = ctx.cstMgr().get(cstRef);
    if (!stored.isSlice())
        return Result::Error;

    DataSegmentRef storedRef;
    if (!ctx.cstMgr().resolveConstantDataSegmentRef(storedRef, cstRef, stored.getSlice().data()))
        return Result::Error;
    if (stored.getSlice().data() == source.data())
        return Result::Error;

    source.fill(std::byte{0});
    if (!std::ranges::equal(stored.getSlice(), std::span{expectedBytes.data(), expectedBytes.size()}))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_AcceptsEmptyBorrowedSlicePayloads)
{
    const TypeRef sliceTypeRef = ctx.typeMgr().addType(TypeInfo::makeSlice(ctx.typeMgr().typeU8()));

    const ConstantRef firstRef  = ctx.cstMgr().addConstant(ctx, ConstantValue::makeSliceBorrowedCounted(ctx, ctx.typeMgr().typeU8(), std::span<const std::byte>{}, 0));
    const ConstantRef secondRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeSliceBorrowedCounted(ctx, ctx.typeMgr().typeU8(), std::span<const std::byte>{}, 0));
    if (!firstRef.isValid() || firstRef != secondRef)
        return Result::Error;

    const ConstantValue& stored = ctx.cstMgr().get(firstRef);
    if (!stored.isSlice() || stored.typeRef() != sliceTypeRef)
        return Result::Error;
    if (!stored.getSlice().empty() || stored.getSliceCount() != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_DistinguishesPresentEmptySlicePayloads)
{
    const TypeRef sliceTypeRef = ctx.typeMgr().addType(TypeInfo::makeSlice(ctx.typeMgr().typeU8()));
    std::array    firstSource{std::byte{0x11}};
    std::array    secondSource{std::byte{0x22}};

    const std::span<const std::byte> firstEmpty{firstSource.data(), 0};
    const std::span<const std::byte> secondEmpty{secondSource.data(), 0};
    const ConstantValue              firstValue = ConstantValue::makeSliceBorrowedCounted(ctx, ctx.typeMgr().typeU8(), firstEmpty, 0);
    if (!firstValue.getSlice().data())
        return Result::Error;

    const ConstantRef firstRef   = ctx.cstMgr().addConstant(ctx, firstValue);
    const ConstantRef secondRef  = ctx.cstMgr().addConstant(ctx, ConstantValue::makeSliceBorrowedCounted(ctx, ctx.typeMgr().typeU8(), secondEmpty, 0));
    const ConstantRef missingRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeSliceBorrowedCounted(ctx, ctx.typeMgr().typeU8(), std::span<const std::byte>{}, 0));
    if (!firstRef.isValid() || firstRef != secondRef || firstRef == missingRef)
        return Result::Error;

    const ConstantValue& stored = ctx.cstMgr().get(firstRef);
    if (!stored.isSlice() || stored.typeRef() != sliceTypeRef || !stored.getSlice().empty() || stored.getSliceCount() != 0)
        return Result::Error;
    if (!stored.getSlice().data() || stored.getSlice().data() == firstSource.data() || stored.getSlice().data() == secondSource.data())
        return Result::Error;

    DataSegmentRef storedRef;
    if (!ctx.cstMgr().resolveConstantDataSegmentRef(storedRef, firstRef, stored.getSlice().data()))
        return Result::Error;

    const ConstantValue& missing = ctx.cstMgr().get(missingRef);
    if (!missing.isSlice() || missing.getSlice().data() || missing.getSliceCount() != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_DeduplicatesMaterializedArrayPayloadConstants)
{
    std::array source{
        std::byte{0xAA},
        std::byte{0xBB},
        std::byte{0xCC},
        std::byte{0xDD},
    };
    std::array    dims{source.size()};
    const TypeRef arrayTypeRef = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));

    DataSegment& segment             = ctx.cstMgr().shardDataSegment(0);
    const auto [storedBytes, offset] = segment.addSpan(std::span{source.data(), source.size()});

    ConstantValue value = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, storedBytes);
    value.setDataSegmentRef({.shardIndex = 0, .offset = offset});

    const ConstantRef firstRef  = ctx.cstMgr().addMaterializedPayloadConstant(value);
    const ConstantRef secondRef = ctx.cstMgr().addMaterializedPayloadConstant(value);
    if (firstRef != secondRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_DoesNotDeduplicateMaterializedArrayPayloadsWithDifferentRelocations)
{
    std::array    dims{sizeof(void*)};
    const TypeRef arrayTypeRef = ctx.typeMgr().addType(TypeInfo::makeArray(std::span<uint64_t>{dims}, ctx.typeMgr().typeU8()));

    DataSegment&   segment = ctx.cstMgr().shardDataSegment(0);
    const uint32_t targetA = segment.reserveBlock(1, 1, true);
    const uint32_t targetB = segment.reserveBlock(1, 1, true);

    const auto [firstOffset, firstStorage]   = segment.reserveBytes(static_cast<uint32_t>(dims[0]), 1, true);
    const auto [secondOffset, secondStorage] = segment.reserveBytes(static_cast<uint32_t>(dims[0]), 1, true);
    segment.addRelocation(firstOffset, targetA);
    segment.addRelocation(secondOffset, targetB);

    ConstantValue firstValue = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{firstStorage, (dims[0])});
    firstValue.setDataSegmentRef({.shardIndex = 0, .offset = firstOffset});

    ConstantValue secondValue = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, std::span{secondStorage, (dims[0])});
    secondValue.setDataSegmentRef({.shardIndex = 0, .offset = secondOffset});

    const ConstantRef firstRef  = ctx.cstMgr().addMaterializedPayloadConstant(firstValue);
    const ConstantRef secondRef = ctx.cstMgr().addMaterializedPayloadConstant(secondValue);
    if (firstRef == secondRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_OwnsAggregateElementsAfterInputsAreDestroyed)
{
    ConstantManager manager;
    const std::array elements = {ctx.cstMgr().addInt(ctx, 31001), ctx.cstMgr().addInt(ctx, 31002), ctx.cstMgr().addInt(ctx, 31003)};
    const std::array names    = {IdentifierRef::invalid(), IdentifierRef::invalid(), IdentifierRef::invalid()};
    ConstantRef     arrayRef;
    ConstantRef     structRef;
    {
        const ConstantValue arrayValue  = ConstantValue::makeAggregateArray(ctx, elements);
        const ConstantValue structValue = ConstantValue::makeAggregateStruct(ctx, names, elements);
        arrayRef                        = manager.addConstant(ctx, arrayValue);
        structRef                       = manager.addConstant(ctx, structValue);
        if (manager.addConstant(ctx, arrayValue) != arrayRef || manager.addConstant(ctx, structValue) != structRef)
            return Result::Error;
        if (manager.get(arrayRef).getAggregateArray().data() == arrayValue.getAggregateArray().data())
            return Result::Error;
        if (manager.get(structRef).getAggregateStruct().data() == structValue.getAggregateStruct().data())
            return Result::Error;
    }

    if (!std::ranges::equal(manager.get(arrayRef).getAggregateArray(), elements))
        return Result::Error;
    if (!std::ranges::equal(manager.get(structRef).getAggregateStruct(), elements))
        return Result::Error;
    if (manager.addConstant(ctx, manager.get(arrayRef)) != arrayRef || manager.addConstant(ctx, manager.get(structRef)) != structRef)
        return Result::Error;
    if (manager.addConstant(ctx, ConstantValue::makeAggregateArray(ctx, elements)) != arrayRef)
        return Result::Error;
    if (manager.addConstant(ctx, ConstantValue::makeAggregateStruct(ctx, names, elements)) != structRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_ReleasesOwnedAggregatePayloads)
{
    // Construct inputs and their interned types before tracking allocations. They belong to
    // the outer compiler and must survive destruction of the isolated constant manager.
    std::vector<ConstantValue> prototypes;
    prototypes.reserve(128);
    const std::array names = {IdentifierRef::invalid(), IdentifierRef::invalid(), IdentifierRef::invalid()};
    for (uint32_t index = 0; index < 64; ++index)
    {
        const std::array elements = {ctx.cstMgr().addInt(ctx, 31001), ctx.cstMgr().addInt(ctx, 31002), ctx.cstMgr().addInt(ctx, 32000 + index)};
        prototypes.push_back(ConstantValue::makeAggregateArray(ctx, elements));
        prototypes.push_back(ConstantValue::makeAggregateStruct(ctx, names, elements));
    }

    Unittest::ScopedHeap heap;
    if (!heap.empty())
        return Result::Error;
    {
        ConstantManager manager;
        for (const ConstantValue& prototype : prototypes)
        {
            const ConstantValue input = prototype;
            const ConstantRef   ref   = manager.addConstant(ctx, input);
            if (manager.addConstant(ctx, input) != ref || manager.addConstant(ctx, manager.get(ref)) != ref)
                return Result::Error;
        }
    }
    if (!heap.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_PreservesStringNormalizationOnRepeatedInputs)
{
    ConstantManager manager;
    auto* aliasSymbol = Symbol::make<SymbolAlias>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    aliasSymbol->setUnderlyingTypeRef(ctx.typeMgr().typeString());
    const TypeRef aliasType = ctx.typeMgr().addType(TypeInfo::makeAlias(aliasSymbol));
    aliasSymbol->setTypeRef(aliasType);
    const TypeRef nullableType = ctx.typeMgr().addType(TypeInfo::makeString(TypeInfoFlagsE::Nullable));

    for (const TypeRef inputType : {aliasType, nullableType})
    {
        ConstantValue value = ConstantValue::makeString(ctx, "normalized-canonical-string");
        value.setTypeRef(inputType);
        const ConstantRef first = manager.addConstant(ctx, value);
        const ConstantValue& stored = manager.get(first);
        const TypeRef expectedType = inputType == aliasType ? ctx.typeMgr().typeString() : nullableType;
        if (stored.typeRef() != expectedType || stored.getString() != value.getString() || value.typeRef() != inputType)
            return Result::Error;
        for (uint32_t repeat = 0; repeat < 8; ++repeat)
        {
            const ConstantRef hit = manager.addConstant(ctx, value);
            if (hit != first || &manager.get(hit) != &stored)
                return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
            if (first.dbgPtr != &stored || hit.dbgPtr != &stored)
                return Result::Error;
#endif
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_PublishesCanonicalReferencesAcrossGrowth)
{
    ConstantManager manager;
    const std::array bytes = {std::byte{0x31}, std::byte{0x52}, std::byte{0x73}};
    const std::array<uint64_t, 1> dims = {bytes.size()};
    const TypeRef arrayType = ctx.typeMgr().addType(TypeInfo::makeArray(dims, ctx.typeMgr().typeU8()));
    const std::array elements = {ctx.cstMgr().addInt(ctx, 34001), ctx.cstMgr().addInt(ctx, 34002)};
    const std::array values = {
        ConstantValue::makeString(ctx, "canonical-reference"),
        ConstantValue::makeArrayBorrowed(ctx, arrayType, bytes),
        ConstantValue::makeAggregateArray(ctx, elements),
    };
    std::array<ConstantRef, values.size()> refs;
    std::array<const ConstantValue*, values.size()> pointers;
    for (size_t index = 0; index < values.size(); ++index)
    {
        refs[index] = manager.addConstant(ctx, values[index]);
        pointers[index] = &manager.get(refs[index]);
#if SWC_HAS_REF_DEBUG_INFO
        if (refs[index].dbgPtr != pointers[index])
            return Result::Error;
#endif
    }

    for (uint32_t index = 0; index < 4096; ++index)
    {
        const std::string text = std::format("canonical-growth-{}", index);
        manager.addConstant(ctx, ConstantValue::makeString(ctx, text));
    }

    for (size_t index = 0; index < values.size(); ++index)
    {
        const ConstantRef inputHit = manager.addConstant(ctx, values[index]);
        const ConstantRef storedHit = manager.addConstant(ctx, *pointers[index]);
        if (inputHit != refs[index] || storedHit != refs[index] || &manager.get(refs[index]) != pointers[index])
            return Result::Error;
        if (!(*pointers[index] == values[index]))
            return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
        if (inputHit.dbgPtr != pointers[index] || storedHit.dbgPtr != pointers[index])
            return Result::Error;
#endif
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_EnrichesStorageReferencesWithoutMutatingInputs)
{
    ConstantManager    manager;
    constexpr uint32_t shardIndex = 3;
    const std::array    bytes      = {std::byte{0x37}, std::byte{0x61}, std::byte{0x94}, std::byte{0xA2}};
    DataSegment&       segment    = manager.shardDataSegment(shardIndex);
    const auto [payload, offset] = segment.addSpan(std::span<const std::byte>(bytes));
    const std::array<uint64_t, 1> dims      = {bytes.size()};
    const TypeRef                 arrayType = ctx.typeMgr().addType(TypeInfo::makeArray(dims, ctx.typeMgr().typeU8()));
    const uint64_t                address   = reinterpret_cast<uint64_t>(payload.data());
    const std::array              values    = {
        ConstantValue::makeArrayBorrowed(ctx, arrayType, payload),
        ConstantValue::makeValuePointer(ctx, ctx.typeMgr().typeU8(), address),
        ConstantValue::makeBlockPointer(ctx, ctx.typeMgr().typeU8(), address),
    };

    for (const ConstantValue& value : values)
    {
        if (value.dataSegmentRef().isValid())
            return Result::Error;
        const ConstantRef ref = manager.addConstant(ctx, value);
        if (value.dataSegmentRef().isValid())
            return Result::Error;
        const ConstantValue& stored    = manager.get(ref);
        const DataSegmentRef storedRef = stored.dataSegmentRef();
        if (storedRef.shardIndex != shardIndex || storedRef.offset != offset)
            return Result::Error;
        const ConstantRef inputHit = manager.addConstant(ctx, value);
        const ConstantRef storedHit = manager.addConstant(ctx, stored);
        if (!(stored == value) || inputHit != ref || storedHit != ref)
            return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
        if (ref.dbgPtr != &stored || inputHit.dbgPtr != &stored || storedHit.dbgPtr != &stored)
            return Result::Error;
#endif
        if (value.dataSegmentRef().isValid())
            return Result::Error;
        if (value.isArray() && ((ref.get() >> ConstantManager::LOCAL_BITS) != shardIndex || stored.getArray().data() != payload.data()))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
