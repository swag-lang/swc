#include "pch.h"
#include "Symbol.Attribute.h"
#include "Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

bool SymbolAttribute::deepCompare(const SymbolAttribute& otherAttr) const noexcept
{
    if (this == &otherAttr)
        return true;

    if (idRef() != otherAttr.idRef())
        return false;
    const auto& params1 = parameters();
    const auto& params2 = otherAttr.parameters();
    if (params1.size() != params2.size())
        return false;

    for (uint32_t i = 0; i < params1.size(); ++i)
    {
        if (params1[i]->typeRef() != params2[i]->typeRef())
            return false;
    }

    return true;
}

SWC_END_NAMESPACE();
