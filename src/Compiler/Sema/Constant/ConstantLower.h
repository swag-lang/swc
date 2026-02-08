#pragma once
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TypeInfo;

namespace ConstantLower
{
    void lowerToBytes(Sema& sema, ByteSpan dstBytes, ConstantRef cstRef, TypeRef dstTypeRef);
    void lowerAggregateArrayToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
    void lowerAggregateStructToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values);
}

SWC_END_NAMESPACE();
