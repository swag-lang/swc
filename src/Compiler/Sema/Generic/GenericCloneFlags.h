#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGeneric::Internal
{
    inline SymbolFlags clonedGenericSymbolFlags(const Symbol& root)
    {
        SymbolFlags flags = SymbolFlagsE::Zero;
        if (root.isPublic())
            flags.add(SymbolFlagsE::Public);
        return flags;
    }
}

SWC_END_NAMESPACE();
