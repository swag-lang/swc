#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace IntrinsicInitType
{
    inline bool preservesAliasType(const TypeInfo& rawType)
    {
        return rawType.isEnum() ||
               rawType.isBool() ||
               rawType.isIntLike() ||
               rawType.isFloat() ||
               rawType.isAnyPointer() ||
               rawType.isReference() ||
               rawType.isCString() ||
               rawType.isTypeInfo() ||
               (rawType.isFunction() && !rawType.isLambdaClosure());
    }
}

SWC_END_NAMESPACE();
