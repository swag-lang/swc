#pragma once
#include "Compiler/Sema/Type/TypeGen.h"

SWC_BEGIN_NAMESPACE();

namespace TypeGenInternal
{
    TypeRef pointerLayoutDepTypeRef(const TypeManager& typeMgr, const TypeInfo& type);
}

SWC_END_NAMESPACE();
