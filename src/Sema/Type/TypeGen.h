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
    Result makeConstantTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, std::string_view& outView);
}

SWC_END_NAMESPACE();
