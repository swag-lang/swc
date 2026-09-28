#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace ConstantHelpers
{
    inline bool isEnumValueType(const TaskContext& ctx, const TypeInfo& originalType, TypeRef typeRef)
    {
        bool isEnumValue = originalType.isEnum();
        if (!isEnumValue && originalType.isAlias())
        {
            const TypeRef unwrappedTypeRef = originalType.unwrap(ctx, typeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
                isEnumValue = ctx.typeMgr().get(unwrappedTypeRef).isEnum();
        }

        return isEnumValue;
    }
}

SWC_END_NAMESPACE();
