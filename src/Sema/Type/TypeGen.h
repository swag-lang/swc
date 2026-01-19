#pragma once
#include "Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace TypeGen
{
    ConstantRef makeConstantTypeInfo(Sema& sema, TypeRef typeRef);
}

SWC_END_NAMESPACE();
