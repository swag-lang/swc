#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;

namespace ConstantLower
{
    void lowerToBytes(Sema& sema, ByteSpanRW dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    void lowerAggregateArrayToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    void lowerAggregateStructToBytes(Sema& sema, ByteSpanRW dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
}

SWC_END_NAMESPACE();
