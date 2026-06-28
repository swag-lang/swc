#pragma once
#include <span>

#include "Support/Core/RefTypes.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;

namespace ConstantLower
{
    Result lowerToBytes(Sema& sema, std::span<std::byte> dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    Result lowerAggregateArrayToBytes(Sema& sema, std::span<std::byte> dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    Result lowerAggregateStructToBytes(Sema& sema, std::span<std::byte> dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    Result materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, std::span<const std::byte> srcBytes);
}

SWC_END_NAMESPACE();
