#include "pch.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ABITypeNormalize::NormalizedType makeNormalizedType(bool isVoid, bool isFloat, uint8_t numBits)
    {
        return ABITypeNormalize::NormalizedType{.isVoid = isVoid, .isFloat = isFloat, .numBits = numBits};
    }

    ABITypeNormalize::NormalizedType makeIndirectStructType(uint32_t copySize, uint32_t copyAlign, bool needsCopy)
    {
        ABITypeNormalize::NormalizedType outType = makeNormalizedType(false, false, 64);
        outType.isIndirect                       = true;
        outType.needsIndirectCopy                = needsCopy;
        outType.indirectSize                     = copySize;
        outType.indirectAlign                    = copyAlign;
        return outType;
    }
}

ABITypeNormalize::NormalizedType ABITypeNormalize::normalize(TaskContext& ctx, const CallConv& conv, TypeRef typeRef, Usage usage)
{
    SWC_ASSERT(typeRef.isValid());

    const TypeRef expanded = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    SWC_ASSERT(expanded.isValid());

    const TypeInfo& ty = ctx.typeMgr().get(expanded);
    if (ty.isVoid())
        return makeNormalizedType(true, false, 0);

    if (ty.isBool())
        return makeNormalizedType(false, false, 8);

    if (ty.isCharRune())
        return makeNormalizedType(false, false, 32);

    if (ty.isInt() && ty.payloadIntBits() <= 64 && ty.payloadIntBits() != 0)
        return makeNormalizedType(false, false, static_cast<uint8_t>(ty.payloadIntBits()));

    if (ty.isFloat() && (ty.payloadFloatBits() == 32 || ty.payloadFloatBits() == 64))
        return makeNormalizedType(false, true, static_cast<uint8_t>(ty.payloadFloatBits()));

    if (ty.isPointerLike() || ty.isNull())
        return makeNormalizedType(false, false, 64);

    if (ty.isStruct())
    {
        const uint64_t rawSize = ty.sizeOf(ctx);
        SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());
        const uint32_t size = static_cast<uint32_t>(rawSize);

        const auto passingKind = usage == Usage::Argument ? conv.classifyStructArgPassing(size) : conv.classifyStructReturnPassing(size);
        if (passingKind == StructArgPassingKind::ByValue)
        {
            SWC_ASSERT(size == 1 || size == 2 || size == 4 || size == 8);
            return makeNormalizedType(false, false, static_cast<uint8_t>(size * 8));
        }

        const uint32_t align     = std::max(ty.alignOf(ctx), uint32_t{1});
        const bool     needsCopy = usage == Usage::Argument && conv.structArgPassing.passByReferenceNeedsCopy;
        return makeIndirectStructType(size, align, needsCopy);
    }

    SWC_ASSERT(false);
    return makeNormalizedType(true, false, 0);
}

SWC_END_NAMESPACE();
