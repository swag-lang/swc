#pragma once
#include "Support/Core/ByteSpan.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;

namespace ConstantLower
{
    void   lowerToBytes(Sema& sema, ByteSpanRW dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    void   lowerAggregateArrayToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    void   lowerAggregateStructToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    Result materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, ByteSpan srcBytes);
}

SWC_END_NAMESPACE();
