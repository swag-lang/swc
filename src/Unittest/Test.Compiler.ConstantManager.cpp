#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool byteSpanEq(ByteSpan lhs, ByteSpan rhs)
    {
        return lhs.size() == rhs.size() && (lhs.empty() || std::memcmp(lhs.data(), rhs.data(), lhs.size()) == 0);
    }
}

SWC_TEST_BEGIN(ConstantManager_CopiesBorrowedStructPayloadOutsideDataSegment)
{
    Runtime::String runtimeString{
        .ptr    = "borrowed-struct",
        .length = 15,
    };
    const char*    expectedPtr    = runtimeString.ptr;
    const uint64_t expectedLength = runtimeString.length;

    const ConstantValue  value  = ConstantValue::makeStructBorrowed(ctx,
                                                                    ctx.typeMgr().typeString(),
                                                                    ByteSpan{reinterpret_cast<const std::byte*>(&runtimeString), sizeof(runtimeString)});
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
    const ConstantValue  value        = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, ByteSpan{source.data(), source.size()});
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
    if (!byteSpanEq(stored.getArray(), ByteSpan{expectedBytes.data(), expectedBytes.size()}))
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

    const ConstantRef firstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, ByteSpan{first.data(), first.size()}));
    const ConstantRef secondRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, ByteSpan{second.data(), second.size()}));
    if (firstRef != secondRef)
        return Result::Error;
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

    const ConstantValue  value  = ConstantValue::makeSliceBorrowed(ctx, ctx.typeMgr().typeU8(), ByteSpan{source.data(), source.size()});
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
    if (!byteSpanEq(stored.getSlice(), ByteSpan{expectedBytes.data(), expectedBytes.size()}))
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

    DataSegment& segment = ctx.cstMgr().shardDataSegment(0);
    const auto [storedBytes, offset] = segment.addSpan(ByteSpan{source.data(), source.size()});

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

    DataSegment& segment = ctx.cstMgr().shardDataSegment(0);
    const uint32_t targetA = segment.reserveBlock(1, 1, true);
    const uint32_t targetB = segment.reserveBlock(1, 1, true);

    const auto [firstOffset, firstStorage] = segment.reserveBytes(static_cast<uint32_t>(dims[0]), 1, true);
    const auto [secondOffset, secondStorage] = segment.reserveBytes(static_cast<uint32_t>(dims[0]), 1, true);
    segment.addRelocation(firstOffset, targetA);
    segment.addRelocation(secondOffset, targetB);

    ConstantValue firstValue = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, ByteSpan{firstStorage, static_cast<size_t>(dims[0])});
    firstValue.setDataSegmentRef({.shardIndex = 0, .offset = firstOffset});

    ConstantValue secondValue = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, ByteSpan{secondStorage, static_cast<size_t>(dims[0])});
    secondValue.setDataSegmentRef({.shardIndex = 0, .offset = secondOffset});

    const ConstantRef firstRef  = ctx.cstMgr().addMaterializedPayloadConstant(firstValue);
    const ConstantRef secondRef = ctx.cstMgr().addMaterializedPayloadConstant(secondValue);
    if (firstRef == secondRef)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
