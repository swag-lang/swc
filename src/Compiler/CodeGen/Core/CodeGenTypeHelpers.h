#pragma once
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenTypeHelpers
{
    inline MicroOpBits bitsFromStorageSize(uint64_t size)
    {
        if (size == 1 || size == 2 || size == 4 || size == 8)
            return microOpBitsFromChunkSize(static_cast<uint32_t>(size));
        return MicroOpBits::Zero;
    }

    inline MicroOpBits numericBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
            return microOpBitsFromBitWidth(typeInfo.payloadFloatBitsOr(64));

        if (typeInfo.isIntLike())
            return microOpBitsFromBitWidth(typeInfo.payloadIntLikeBitsOr(64));

        return MicroOpBits::Zero;
    }

    inline MicroOpBits numericOrBoolBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isBool())
            return MicroOpBits::B8;
        return numericBits(typeInfo);
    }

    inline MicroOpBits copyBits(const TypeInfo& typeInfo)
    {
        if (const auto bits = numericBits(typeInfo); bits != MicroOpBits::Zero)
            return bits;
        return MicroOpBits::B64;
    }

    inline MicroOpBits conditionBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        if (const auto bits = bitsFromStorageSize(typeInfo.sizeOf(ctx)); bits != MicroOpBits::Zero)
            return bits;
        return MicroOpBits::B64;
    }

    inline MicroOpBits compareBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        if (const auto bits = numericOrBoolBits(typeInfo); bits != MicroOpBits::Zero)
            return bits;
        return conditionBits(typeInfo, ctx);
    }

    inline MicroOpBits scalarStoreBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        if (const auto bits = numericOrBoolBits(typeInfo); bits != MicroOpBits::Zero)
            return bits;

        if (typeInfo.isEnum() || typeInfo.isAnyPointer() || (typeInfo.isFunction() && !typeInfo.isLambdaClosure()) || typeInfo.isCString() || typeInfo.isTypeInfo())
            return bitsFromStorageSize(typeInfo.sizeOf(ctx));

        return MicroOpBits::Zero;
    }

    inline uint64_t blockPointerStride(TaskContext& ctx, const TypeInfo& pointerType)
    {
        SWC_ASSERT(pointerType.isBlockPointer());
        const uint64_t stride = ctx.typeMgr().get(pointerType.payloadTypeRef()).sizeOf(ctx);
        SWC_ASSERT(stride > 0);
        return stride;
    }
}

SWC_END_NAMESPACE();
