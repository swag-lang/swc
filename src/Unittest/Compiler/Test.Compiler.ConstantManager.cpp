#include "pch.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"

#if SWC_HAS_UNITTEST

#include "Backend/RuntimeBase.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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
    ConstantManager  manager;
    const std::array elements = {ctx.cstMgr().addInt(ctx, 31001), ctx.cstMgr().addInt(ctx, 31002), ctx.cstMgr().addInt(ctx, 31003)};
    const std::array names    = {IdentifierRef::invalid(), IdentifierRef::invalid(), IdentifierRef::invalid()};
    ConstantRef      arrayRef;
    ConstantRef      structRef;
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
    auto*           aliasSymbol = Symbol::make<SymbolAlias>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    aliasSymbol->setUnderlyingTypeRef(ctx.typeMgr().typeString());
    const TypeRef aliasType = ctx.typeMgr().addType(TypeInfo::makeAlias(aliasSymbol));
    aliasSymbol->setTypeRef(aliasType);
    const TypeRef nullableType = ctx.typeMgr().addType(TypeInfo::makeString(TypeInfoFlagsE::Nullable));

    const std::string longText(4097, 'x');
    const std::array  texts = {std::string_view{}, std::string_view{"normalized-canonical-string"}, std::string_view{"embedded\0null", 13}, std::string_view{"utf8-\xC3\xA9"}, std::string_view{longText}};

    for (const TypeRef inputType : {ctx.typeMgr().typeString(), aliasType, nullableType})
    {
        for (const std::string_view text : texts)
        {
            ConstantValue value = ConstantValue::makeString(ctx, text);
            value.setTypeRef(inputType);
            const ConstantRef    first        = manager.addConstant(ctx, value);
            const ConstantValue& stored       = manager.get(first);
            const DataSegment&   segment      = manager.shardDataSegment(first.get() >> ConstantStorageLayout::LOCAL_BITS);
            const uint32_t       extent       = segment.extentSize();
            const TypeRef        expectedType = inputType == aliasType ? ctx.typeMgr().typeString() : inputType;
            if (stored.typeRef() != expectedType || stored.getString() != value.getString() || value.typeRef() != inputType)
                return Result::Error;
            for (uint32_t repeat = 0; repeat < 8; ++repeat)
            {
                const ConstantRef hit = manager.addConstant(ctx, value);
                if (hit != first || &manager.get(hit) != &stored || segment.extentSize() != extent)
                    return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
                if (first.dbgPtr != &stored || hit.dbgPtr != &stored)
                    return Result::Error;
#endif
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_PublishesCanonicalReferencesAcrossGrowth)
{
    ConstantManager               manager;
    const std::array              bytes     = {std::byte{0x31}, std::byte{0x52}, std::byte{0x73}};
    const std::array<uint64_t, 1> dims      = {bytes.size()};
    const TypeRef                 arrayType = ctx.typeMgr().addType(TypeInfo::makeArray(dims, ctx.typeMgr().typeU8()));
    const std::array              elements  = {ctx.cstMgr().addInt(ctx, 34001), ctx.cstMgr().addInt(ctx, 34002)};
    const std::array              values    = {
        ConstantValue::makeString(ctx, "canonical-reference"),
        ConstantValue::makeArrayBorrowed(ctx, arrayType, bytes),
        ConstantValue::makeAggregateArray(ctx, elements),
    };
    std::array<ConstantRef, values.size()>          refs;
    std::array<const ConstantValue*, values.size()> pointers;
    for (size_t index = 0; index < values.size(); ++index)
    {
        refs[index]     = manager.addConstant(ctx, values[index]);
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
        const ConstantRef inputHit  = manager.addConstant(ctx, values[index]);
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
    constexpr uint32_t shardIndex           = 3;
    const std::array   bytes                = {std::byte{0x37}, std::byte{0x61}, std::byte{0x94}, std::byte{0xA2}};
    DataSegment&       segment              = manager.shardDataSegment(shardIndex);
    const auto [payload, offset]            = segment.addSpan(std::span<const std::byte>(bytes));
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
        const ConstantRef inputHit  = manager.addConstant(ctx, value);
        const ConstantRef storedHit = manager.addConstant(ctx, stored);
        if (!(stored == value) || inputHit != ref || storedHit != ref)
            return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
        if (ref.dbgPtr != &stored || inputHit.dbgPtr != &stored || storedHit.dbgPtr != &stored)
            return Result::Error;
#endif
        if (value.dataSegmentRef().isValid())
            return Result::Error;
        if (value.isArray() && ((ref.get() >> ConstantStorageLayout::LOCAL_BITS) != shardIndex || stored.getArray().data() != payload.data()))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_ConcurrentInterningKeepsCanonicalStorage)
{
    constexpr size_t NUM_WORKERS = 2;
    constexpr size_t NUM_VALUES  = 128;
    constexpr size_t NUM_FIELDS  = 32;

    ConstantManager                                                       manager;
    std::barrier                                                          rendezvous(NUM_WORKERS);
    std::array<std::array<ConstantRef, NUM_VALUES>, NUM_WORKERS>          commonRefs;
    std::array<std::array<ConstantRef, NUM_VALUES>, NUM_WORKERS>          uniqueRefs;
    std::array<std::array<const ConstantValue*, NUM_VALUES>, NUM_WORKERS> addresses;
    std::array<ConstantRef, NUM_VALUES*(NUM_WORKERS + 1)>                 elements;
    std::array<bool, NUM_WORKERS>                                         valid = {true, true};
    for (size_t index = 0; index < elements.size(); ++index)
        elements[index] = ctx.cstMgr().addInt(ctx, 35000 + index);

    {
        // Prepare types and owned inputs before the workers start. Each worker then
        // copies its input locally; all source vectors die before the final checks.
        std::vector<ConstantValue>                          commonInputs;
        std::array<std::vector<ConstantValue>, NUM_WORKERS> uniqueInputs;
        std::array<ConstantRef, NUM_FIELDS>                 fields;
        fields.fill(elements[0]);
        commonInputs.reserve(NUM_VALUES);
        for (auto& inputs : uniqueInputs)
            inputs.reserve(NUM_VALUES);
        for (size_t index = 0; index < NUM_VALUES; ++index)
        {
            fields.back() = elements[index];
            commonInputs.push_back(ConstantValue::makeAggregateArray(ctx, fields));
            for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
            {
                fields.back() = elements[NUM_VALUES * (worker + 1) + index];
                uniqueInputs[worker].push_back(ConstantValue::makeAggregateArray(ctx, fields));
            }
        }

        std::array<std::thread, NUM_WORKERS> workers;
        for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
        {
            workers[worker] = std::thread([&, worker] {
                TaskContext workerCtx(ctx);
                for (size_t index = 0; index < NUM_VALUES; ++index)
                {
                    const ConstantValue common = commonInputs[index];
                    const ConstantValue unique = uniqueInputs[worker][index];
                    rendezvous.arrive_and_wait();
                    const ConstantRef ref     = manager.addConstant(workerCtx, common);
                    commonRefs[worker][index] = ref;
                    addresses[worker][index]  = &manager.get(ref);
                    uniqueRefs[worker][index] = manager.addConstant(workerCtx, unique);
                    const ConstantRef hit     = manager.addConstant(workerCtx, common);
                    if (hit != ref || addresses[worker][index]->getAggregateArray().data() == common.getAggregateArray().data())
                        valid[worker] = false;
#if SWC_HAS_REF_DEBUG_INFO
                    if (ref.dbgPtr != addresses[worker][index] || hit.dbgPtr != addresses[worker][index])
                        valid[worker] = false;
#endif
                }
            });
        }
        for (auto& worker : workers)
            worker.join();
    }

    std::unordered_set<ConstantRef> allRefs;
    for (size_t index = 0; index < NUM_VALUES; ++index)
    {
        if (commonRefs[0][index] != commonRefs[1][index])
            return Result::Error;
        allRefs.insert(commonRefs[0][index]);
        for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
        {
            if (!valid[worker])
                return Result::Error;
            const ConstantRef    ref    = commonRefs[worker][index];
            const ConstantValue& stored = manager.get(ref);
            const auto&          fields = stored.getAggregateArray();
            if (&stored != addresses[worker][index] || fields.size() != NUM_FIELDS || fields.back() != elements[index])
                return Result::Error;
            for (size_t field = 0; field + 1 < fields.size(); ++field)
                if (fields[field] != elements[0])
                    return Result::Error;
            const ConstantRef hit = manager.addConstant(ctx, stored);
            if (hit != ref)
                return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
            if (ref.dbgPtr != &stored || hit.dbgPtr != &stored)
                return Result::Error;
#endif
            const ConstantRef unique = uniqueRefs[worker][index];
            allRefs.insert(unique);
            if (manager.get(unique).getAggregateArray().back() != elements[NUM_VALUES * (worker + 1) + index])
                return Result::Error;
        }
    }
    if (allRefs.size() != NUM_VALUES * (NUM_WORKERS + 1))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_ReleasesRelocationWalksWithTheirOwner)
{
    // Reconstruct at the same address while the calling thread stays alive. A TLS shortcut
    // must distinguish the new owner, and every old cache allocation must have been freed.
    std::optional<ConstantManager> manager;
    for (uint32_t generation = 0; generation < 2; ++generation)
    {
        Unittest::ScopedHeap heap;
        manager.emplace();
        auto&      segment = manager->shardDataSegment(0);
        const auto offset  = segment.reserveSpan<uint64_t>(8).first;
        for (uint32_t index = 0; index < 8; ++index)
            segment.addRelocation(offset + index * sizeof(uint64_t), offset);

        // Eight relocations also exercise the cache entry's heap-backed payload.
        const auto* walked = manager->walkedAllocation(0, offset);
        const bool  valid  = walked && walked->relocations.size() == 8 && walked->dataOnlyRelocationVersions == 0;
        if (walked)
            walked->dataOnlyRelocationVersions = 123;
        manager.reset();
        const bool released = heap.empty();
        heap.release();
        if (!valid || !released)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_RelocationWalkPreservesOffsetsAndInterleavedOwners)
{
    std::array<std::unique_ptr<ConstantManager>, 2>                        managers;
    std::array<std::array<const ConstantManager::WalkedAllocation*, 3>, 2> entries{};
    std::array<uint32_t, 2>                                                offsets{};
    for (uint32_t owner = 0; owner < managers.size(); ++owner)
    {
        managers[owner] = std::make_unique<ConstantManager>();
        offsets[owner]  = managers[owner]->shardDataSegment(0).reserveSpan<std::byte>(3).first;
        for (uint32_t index = 0; index < entries[owner].size(); ++index)
        {
            const auto* walked = managers[owner]->walkedAllocation(0, offsets[owner] + index);
            if (!walked || walked->allocation.offset != offsets[owner])
                return Result::Error;
            walked->dataOnlyRelocationVersions = 100 + owner * 10 + index;
            entries[owner][index]              = walked;
        }
    }

    // Neighboring byte offsets must have distinct stable entries. Switching back to a live
    // owner must reuse its table rather than discard work or invalidate retained pointers.
    for (uint32_t owner = 0; owner < managers.size(); ++owner)
    {
        for (uint32_t index = 0; index < entries[owner].size(); ++index)
        {
            const auto* walked = managers[owner]->walkedAllocation(0, offsets[owner] + index);
            if (walked != entries[owner][index] || walked->dataOnlyRelocationVersions != 100 + owner * 10 + index)
                return Result::Error;
        }
        if (managers[owner]->walkedAllocation(0, INVALID_REF))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_RelocationWalkKeepsThreadsIndependent)
{
    ConstantManager                                         manager;
    const auto                                              offset = manager.shardDataSegment(0).reserveSpan<uint64_t>(1).first;
    std::array<const ConstantManager::WalkedAllocation*, 2> entries{};
    std::array<std::thread, 2>                              workers;
    std::barrier                                            ready(2);
    std::atomic<bool>                                       failed = false;
    for (uint32_t index = 0; index < workers.size(); ++index)
    {
        workers[index] = std::thread([&, index] {
            entries[index] = manager.walkedAllocation(0, offset);
            ready.arrive_and_wait();
            if (!entries[index] || entries[0] == entries[1])
            {
                failed.store(true, std::memory_order_relaxed);
                return;
            }
            entries[index]->dataOnlyRelocationVersions = index + 1;
            if (manager.walkedAllocation(0, offset) != entries[index] || entries[index]->dataOnlyRelocationVersions != index + 1)
                failed.store(true, std::memory_order_relaxed);
        });
    }
    for (auto& worker : workers)
        worker.join();
    if (failed.load(std::memory_order_relaxed))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_ChecksSharedRelocationGraphsPerQuery)
{
    ConstantManager manager;
    auto&           leftSegment            = manager.shardDataSegment(0);
    auto&           rightSegment           = manager.shardDataSegment(1);
    const auto [leftOffset, leftStorage]   = leftSegment.reserveSpan<uint64_t>(2);
    const auto [rightOffset, rightStorage] = rightSegment.reserveSpan<uint64_t>(2);
    SWC_UNUSED(leftStorage);
    SWC_UNUSED(rightStorage);
    const DataSegmentRef left{.shardIndex = 0, .offset = leftOffset};
    const DataSegmentRef right{.shardIndex = 1, .offset = rightOffset};
    leftSegment.addRelocation(leftOffset, right);
    rightSegment.addRelocation(rightOffset, left);

    std::array<DataSegmentRef, 128> roots;
    for (uint32_t i = 0; i < roots.size(); ++i)
        roots[i] = i % 2 ? left : right;
    // Interior addresses identify the same allocations as their base addresses.
    roots.back().offset += sizeof(uint64_t);
    if (manager.hasUnpublishedFunctionRelocations({}) || manager.hasUnpublishedFunctionRelocations(roots))
        return Result::Error;

    auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier("relocation_query_target"), SymbolFlagsE::Zero);
    rightSegment.addFunctionRelocation(rightOffset + sizeof(uint64_t), function, true);
    if (!manager.hasUnpublishedFunctionRelocations(roots))
        return Result::Error;

    // Query-local membership must not hide changes between checks. Foreign
    // targets are stable external addresses and do not need a compiler JIT entry.
    AttributeList attributes;
    attributes.hasForeign = true;
    function->setAttributes(ctx, attributes);
    if (manager.hasUnpublishedFunctionRelocations(roots))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_RelocationWalkHandlesTableGrowth)
{
    ConstantManager                  manager;
    auto&                            segment = manager.shardDataSegment(0);
    std::array<DataSegmentRef, 4096> roots;
    for (DataSegmentRef& root : roots)
        root = {.shardIndex = 0, .offset = segment.reserveSpan<uint64_t>(1).first};

    auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier("relocation_growth_target"), SymbolFlagsE::Zero);
    bool  failed   = false;

    // A fresh worker starts with an empty walk cache, so these roots force its table to grow.
    std::thread worker([&] {
        if (manager.hasUnpublishedFunctionRelocations(roots))
        {
            failed = true;
            return;
        }

        segment.addFunctionRelocation(roots.back().offset, function, true);
        if (!manager.hasUnpublishedFunctionRelocations(roots))
            failed = true;
        if (manager.hasUnpublishedFunctionRelocations(std::span(roots).first(roots.size() - 1)))
            failed = true;
    });
    worker.join();

    if (failed)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_SourceLocationsShareCompleteStorage)
{
    ConstantManager             manager;
    const TypeRef               type = ctx.typeMgr().typeString();
    Runtime::SourceCodeLocation location{
        .fileName  = {.ptr = "shared.swg", .length = 10},
        .funcName  = {.ptr = "sample", .length = 6},
        .lineStart = 12,
        .colStart  = 3,
        .lineEnd   = 12,
        .colEnd    = 9,
    };
    const ConstantRef first         = manager.addSourceCodeLocation(ctx, type, location);
    const auto        dataRef       = manager.get(first).dataSegmentRef();
    const auto&       segment       = manager.shardDataSegment(dataRef.shardIndex);
    const uint32_t    sizeBefore    = segment.size();
    const uint64_t    versionBefore = segment.relocationVersion();
    // Equal text at a different address must still share its location and relocations.
    const std::string fileName     = "shared.swg";
    const std::string functionName = "sample";
    location.fileName.ptr          = fileName.data();
    location.funcName.ptr          = functionName.data();
    for (uint32_t i = 0; i < 128; ++i)
        if (manager.addSourceCodeLocation(ctx, type, location) != first)
            return Result::Error;
    if (segment.size() != sizeBefore || segment.relocationVersion() != versionBefore)
        return Result::Error;
    const auto* stored = manager.get(first).getStruct<Runtime::SourceCodeLocation>(type);
    if (std::string_view(stored->fileName.ptr, stored->fileName.length) != fileName || std::string_view(stored->funcName.ptr, stored->funcName.length) != functionName)
        return Result::Error;
    const auto relocations = segment.copyRelocations();
    if (relocations.size() != 2)
        return Result::Error;
    for (const auto& relocation : relocations)
    {
        const char* expected = relocation.offset == dataRef.offset ? stored->fileName.ptr : stored->funcName.ptr;
        if (segment.ptr<char>(relocation.targetOffset) != expected)
            return Result::Error;
    }
    for (uint32_t field = 0; field < 7; ++field)
    {
        auto    different     = location;
        TypeRef differentType = type;
        switch (field)
        {
            case 0: different.fileName = {.ptr = "other.swg", .length = 9}; break;
            case 1: different.funcName = {}; break;
            case 2: different.lineStart++; break;
            case 3: different.colStart++; break;
            case 4: different.lineEnd++; break;
            case 5: different.colEnd++; break;
            case 6: differentType = ctx.typeMgr().typeU64(); break;
        }
        if (manager.addSourceCodeLocation(ctx, differentType, different) == first)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ConstantManager_SourceLocationsPublishOnceAcrossWorkers)
{
    ConstantManager                                                 manager;
    constexpr size_t                                                workerCount   = 6;
    constexpr size_t                                                locationCount = 32;
    const TypeRef                                                   type          = ctx.typeMgr().typeString();
    std::array<std::array<ConstantRef, locationCount>, workerCount> refs;
    std::array<std::thread, workerCount>                            workers;
    std::barrier                                                    rendezvous(workerCount);
    for (size_t worker = 0; worker < workerCount; ++worker)
    {
        workers[worker] = std::thread([&, worker] {
            TaskContext                 workerCtx(ctx);
            Runtime::SourceCodeLocation location{
                .fileName  = {.ptr = "parallel.swg", .length = 12},
                .funcName  = {},
                .lineStart = 1,
                .colStart  = 1,
                .lineEnd   = 1,
                .colEnd    = 2,
            };
            for (uint32_t i = 0; i < locationCount; ++i)
            {
                location.lineStart = i + 1;
                location.lineEnd   = i + 1;
                rendezvous.arrive_and_wait();
                refs[worker][i] = manager.addSourceCodeLocation(workerCtx, type, location);
            }
        });
    }
    for (auto& worker : workers)
        worker.join();
    for (size_t worker = 0; worker < workerCount; ++worker)
        for (size_t i = 0; i < locationCount; ++i)
            if (refs[worker][i] != refs[0][i])
                return Result::Error;
    uint64_t relocationCount = 0;
    for (uint32_t i = 0; i < ConstantStorageLayout::SHARD_COUNT; ++i)
        relocationCount += manager.shardDataSegment(i).copyRelocations().size();
    if (relocationCount != locationCount)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
