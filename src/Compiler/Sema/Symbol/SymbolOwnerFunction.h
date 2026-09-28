#pragma once
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

namespace SymbolOwnerFunction
{
    inline const SymbolFunction* nearest(const SymbolMap* map) noexcept
    {
        while (map)
        {
            if (map->isFunction())
                return &map->cast<SymbolFunction>();
            map = map->ownerSymMap();
        }

        return nullptr;
    }
}

SWC_END_NAMESPACE();
