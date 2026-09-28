#pragma once
#include "Compiler/Sema/Cast/Cast.h"

SWC_BEGIN_NAMESPACE();

namespace CastElementHelpers
{
    inline Result allowed(Sema& sema, CastRequest& parentRequest, CastRequest& elemRequest, TypeRef srcElemType, TypeRef dstElemType)
    {
        const Result res = Cast::castAllowed(sema, elemRequest, srcElemType, dstElemType);
        if (res != Result::Continue)
            parentRequest.failure = elemRequest.failure;
        return res;
    }

    inline Result foldConstant(Sema& sema, CastRequest& parentRequest, CastRequest& elemRequest, TypeRef srcElemType, TypeRef dstElemType, ConstantRef valueRef, ConstantRef& outRef)
    {
        elemRequest.setConstantFoldingSrc(valueRef);
        const Result res = allowed(sema, parentRequest, elemRequest, srcElemType, dstElemType);
        if (res != Result::Continue)
            return res;

        outRef = elemRequest.constantFoldingResult();
        if (srcElemType != dstElemType)
        {
            SWC_RESULT(Cast::castConstant(sema, outRef, elemRequest, valueRef, dstElemType));
            return Result::Continue;
        }

        if (outRef.isInvalid())
            outRef = valueRef;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
