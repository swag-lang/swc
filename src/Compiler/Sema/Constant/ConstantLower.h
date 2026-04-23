#pragma once
#include "Support/Core/ByteSpan.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;

namespace ConstantLower
{
    struct MaterializedPayloadResult
    {
        uint32_t   offset = INVALID_REF;
        ByteSpanRW bytes;
    };

    Result lowerToBytes(Sema& sema, ByteSpanRW dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    Result lowerAggregateArrayToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    Result lowerAggregateStructToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    Result materializeStaticPayload(MaterializedPayloadResult& outPayload, Sema& sema, DataSegment& segment, TypeRef typeRef, ByteSpan srcBytes);
    Result materializeStaticPayload(uint32_t& outOffset, Sema& sema, DataSegment& segment, TypeRef typeRef, ByteSpan srcBytes);
}

SWC_END_NAMESPACE();
