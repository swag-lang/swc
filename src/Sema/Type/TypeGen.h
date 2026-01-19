#pragma once
#include "Parser/AstNode.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();
class DataSegment;

namespace TypeGen
{
    struct TypeGenResult
    {
        std::string_view view;
        TypeRef          structTypeRef;
    };

    Result makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result);
}

SWC_END_NAMESPACE();
