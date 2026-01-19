#pragma once
#include "Core/StrongRef.h"

#include "Parser/AstNode.h"
#include "Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();
class DataSegment;
class TypeInfo;
using TypeRef = StrongRef<TypeInfo>;

namespace TypeGen
{
    struct ConstantTypeInfoResult
    {
        std::string_view view;
        TypeRef          structTypeRef;
    };

    Result makeConstantTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, ConstantTypeInfoResult& result);
}

SWC_END_NAMESPACE();
