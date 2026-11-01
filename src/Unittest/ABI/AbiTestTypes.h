#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();
class TaskContext;

#if SWC_HAS_UNITTEST
namespace Backend::Unittest
{
    TypeRef makeStructType(TaskContext& ctx, std::span<const TypeRef> fieldTypes, bool isUnion = false, TypeRef tagType = TypeRef::invalid());
}
#endif
SWC_END_NAMESPACE();
