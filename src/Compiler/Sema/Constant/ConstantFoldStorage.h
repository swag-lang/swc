#pragma once
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace ConstantHelpers
{
    inline TypeRef constantFoldStorageTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAlias() && !typeInfo.isEnum())
            return typeRef;

        const TypeRef storageTypeRef = typeInfo.unwrapAliasEnum(sema.ctx(), typeRef);
        return storageTypeRef.isValid() ? storageTypeRef : typeRef;
    }
}

SWC_END_NAMESPACE();
