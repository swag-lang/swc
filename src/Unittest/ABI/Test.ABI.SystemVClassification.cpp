#include "pch.h"

#if SWC_HAS_UNITTEST
#include "Backend/ABI/SystemVAbi.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Unittest/ABI/AbiTestTypes.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using SystemVAbi::Class;

    bool hasClasses(TaskContext& ctx, const TypeRef type, const std::array<Class, 2> classes, const uint32_t size, const uint32_t alignment)
    {
        const auto result = SystemVAbi::classify(ctx, ctx.typeMgr().get(type));
        return result && result->classes == classes && result->size == size && result->alignment == alignment;
    }
}

SWC_TEST_BEGIN(ABI_SystemVClassifiesMixedAndNestedStorage)
{
    auto& types = ctx.typeMgr();
    const std::array mixedFields{types.typeF64(), types.typeU32()};
    const auto mixed = Backend::Unittest::makeStructType(ctx, mixedFields);
    struct Mixed { double floating; uint32_t integer; };
    if (!hasClasses(ctx, mixed, {Class::Sse, Class::Integer}, sizeof(Mixed), alignof(Mixed)))
        return Result::Error;

    const std::array sharedFields{types.typeF32(), types.typeU32()};
    const auto shared = Backend::Unittest::makeStructType(ctx, sharedFields);
    if (!hasClasses(ctx, shared, {Class::Integer, Class::None}, 8, 4))
        return Result::Error;
    const std::array nestedFields{shared, types.typeF64()};
    const auto nested = Backend::Unittest::makeStructType(ctx, nestedFields);
    if (!hasClasses(ctx, nested, {Class::Integer, Class::Sse}, 16, 8))
        return Result::Error;

    const std::array<uint64_t, 1> dimensions{3};
    const auto array = types.addType(TypeInfo::makeArray(dimensions, types.typeF32()));
    const std::array arrayFields{array};
    const auto wrappedArray = Backend::Unittest::makeStructType(ctx, arrayFields);
    if (!hasClasses(ctx, wrappedArray, {Class::Sse, Class::Sse}, sizeof(float[3]), alignof(float[3])))
        return Result::Error;
    if (!hasClasses(ctx, types.typeString(), {Class::Integer, Class::Integer}, 16, 8))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVClassifiesUnionsAndVectorUpperHalves)
{
    auto& types = ctx.typeMgr();
    const auto vector = types.addType(TypeInfo::makeSimd(types.typeF32(), 4));
    if (!hasClasses(ctx, vector, {Class::Sse, Class::SseUp}, 16, 16))
        return Result::Error;
    const std::array fields{vector, types.typeU64()};
    const auto overlay = Backend::Unittest::makeStructType(ctx, fields, true);
    if (!hasClasses(ctx, overlay, {Class::Integer, Class::Sse}, 16, 16))
        return Result::Error;

    const std::array taggedFields{types.typeF64(), types.typeU32()};
    const auto tagged = Backend::Unittest::makeStructType(ctx, taggedFields, true, types.typeU32());
    if (!hasClasses(ctx, tagged, {Class::Integer, Class::Integer}, 16, 8))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVPlacesLargeAndUnalignedRecordsInMemory)
{
    auto& types = ctx.typeMgr();
    const std::array largeFields{types.typeU64(), types.typeU64(), types.typeU64()};
    const auto large = Backend::Unittest::makeStructType(ctx, largeFields);
    if (!hasClasses(ctx, large, {Class::Memory, Class::None}, 24, 8))
        return Result::Error;

    // A packed field inside an explicitly eight-aligned record: the total
    // size/alignment do not reveal the unaligned member that forces MEMORY.
    const std::array packedFields{types.typeU8(), types.typeF64()};
    const auto packed = Backend::Unittest::makeStructType(ctx, packedFields);
    types.get(packed).payloadSymStruct().fields()[1]->setOffset(1);
    if (!hasClasses(ctx, packed, {Class::Memory, Class::None}, 16, 8))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVRollsBackBothBanksForAnAggregate)
{
    const SystemVAbi::Classification integer{{Class::Integer, Class::None}, 8, 8};
    const SystemVAbi::Classification floating{{Class::Sse, Class::None}, 8, 8};
    const SystemVAbi::Classification mixed{{Class::Integer, Class::Sse}, 16, 8};
    for (const bool exhaustInteger : {false, true})
    {
        SystemVAbi::ArgumentAllocator allocator;
        for (uint32_t index = 0; index < (exhaustInteger ? 6u : 8u); ++index)
        {
            if (allocator.next(exhaustInteger ? integer : floating).onStack)
                return Result::Error;
        }
        const auto spilled = allocator.next(mixed);
        if (!spilled.onStack || spilled.stackOffset || allocator.stackSize() != 16)
            return Result::Error;
        const auto remaining = allocator.next(exhaustInteger ? floating : integer);
        if (remaining.onStack || remaining.registers[0] != 0)
            return Result::Error;
        const auto exhausted = allocator.next(exhaustInteger ? integer : floating);
        if (!exhausted.onStack || exhausted.stackOffset != 16)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVVectorUpperHalfSharesOneRegister)
{
    SystemVAbi::ArgumentAllocator allocator;
    const SystemVAbi::Classification vector{{Class::Sse, Class::SseUp}, 16, 16};
    for (uint32_t index = 0; index < 8; ++index)
    {
        const auto location = allocator.next(vector);
        if (location.onStack || location.registers[0] != index || location.registers[1] != index)
            return Result::Error;
    }
    const auto spilled = allocator.next(vector);
    if (!spilled.onStack || spilled.stackOffset || allocator.stackSize() != 16 || allocator.vectorRegisters() != 8)
        return Result::Error;
    const SystemVAbi::Classification wide{{Class::Memory, Class::None}, 32, 32};
    const auto aligned = allocator.next(wide);
    if (!aligned.onStack || aligned.stackOffset != 32 || allocator.stackSize() != 64 || allocator.stackAlignment() != 32)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVNormalizedStorageDistinguishesStackValuesAndHiddenResults)
{
    auto& types = ctx.typeMgr();
    const auto& conv = CallConv::get(CallConvKind::SystemVAMD64);
    const std::array mixedFields{types.typeU64(), types.typeF64()};
    const TypeRef mixed = Backend::Unittest::makeStructType(ctx, mixedFields);
    for (const auto usage : {ABITypeNormalize::Usage::Argument, ABITypeNormalize::Usage::Return})
    {
        const auto normalized = ABITypeNormalize::normalize(ctx, conv, types.get(mixed), usage);
        const auto storage = normalized.systemVStorageType();
        if (!normalized.isSystemVStorage() || normalized.isIndirect || normalized.needsIndirectCopy || storage.size != 16 || storage.alignment != 8)
            return Result::Error;
        if (storage.classes != std::array{Class::Integer, Class::Sse})
            return Result::Error;
    }
    const std::array largeFields{types.typeU64(), types.typeU64(), types.typeU64()};
    const TypeRef large = Backend::Unittest::makeStructType(ctx, largeFields);
    const auto argument = ABITypeNormalize::normalize(ctx, conv, types.get(large), ABITypeNormalize::Usage::Argument);
    const auto result = ABITypeNormalize::normalize(ctx, conv, types.get(large), ABITypeNormalize::Usage::Return);
    if (!argument.isSystemVStorage() || !argument.systemVStorageType().memory() || argument.isIndirect || argument.needsIndirectCopy)
        return Result::Error;
    if (!result.isSystemVStorage() || !result.systemVStorageType().memory() || !result.isIndirect || result.indirectSize != 24)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SystemVNormalizationKeepsArrayDecayAndWideRegisterShapes)
{
    auto& types = ctx.typeMgr();
    const auto& conv = CallConv::get(CallConvKind::SystemVAMD64);
    const std::array<uint64_t, 1> dimensions{3};
    const auto array = types.addType(TypeInfo::makeArray(dimensions, types.typeU64()));
    const auto argument = ABITypeNormalize::normalize(ctx, conv, types.get(array), ABITypeNormalize::Usage::Argument);
    if (!argument.isIndirect || argument.isSystemVStorage() || argument.needsIndirectCopy || argument.numBits != 64)
        return Result::Error;
    const auto integer = types.addType(TypeInfo::makeInt(128, TypeInfo::Sign::Unsigned));
    const auto wide = ABITypeNormalize::normalize(ctx, conv, types.get(integer), ABITypeNormalize::Usage::Argument);
    if (!wide.isSystemVStorage() || wide.isIndirect || wide.systemVStorageType().classes != std::array{Class::Integer, Class::Integer})
        return Result::Error;
    const auto vector = types.addType(TypeInfo::makeSimd(types.typeF32(), 4));
    for (const auto usage : {ABITypeNormalize::Usage::Argument, ABITypeNormalize::Usage::Return})
    {
        const auto normalized = ABITypeNormalize::normalize(ctx, conv, types.get(vector), usage);
        if (normalized.isSystemVStorage() || normalized.isIndirect || !normalized.isFloat || normalized.numBits != 128)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
