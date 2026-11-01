#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();
class TaskContext;
class SourceFile;

#if SWC_HAS_UNITTEST
namespace Backend::Unittest
{
    SourceFile& makeCodeGenSource(TaskContext& ctx, std::string_view testName, std::string_view source = "");
    TypeRef makeStructType(TaskContext& ctx, std::span<const TypeRef> fieldTypes, bool isUnion = false, TypeRef tagType = TypeRef::invalid());
}
#endif
SWC_END_NAMESPACE();
