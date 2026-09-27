#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenArraySlice
{
    inline uint64_t sliceCountFromArrayCast(CodeGen& codeGen, const TypeInfo& srcArrayType, const TypeInfo& dstElementType)
    {
        const uint64_t dstElementSize = dstElementType.sizeOf(codeGen.ctx());
        if (dstElementSize)
            return srcArrayType.sizeOf(codeGen.ctx()) / dstElementSize;

        uint64_t totalCount = 1;
        for (const uint64_t dim : srcArrayType.payloadArrayDims())
            totalCount *= dim;
        return totalCount;
    }
}

SWC_END_NAMESPACE();
