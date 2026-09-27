#pragma once
#include "Compiler/Sema/Core/Sema.h"

#include <memory>

SWC_BEGIN_NAMESPACE();

namespace SemaDeclHelpers
{
    template<typename T>
    inline Sema* tryCreateForSymbol(Sema& sema, const T& symbol, std::unique_ptr<Sema>& ownedSema)
    {
        return sema.tryCreateDeclSema(ownedSema, symbol.srcViewRef(), symbol.decl(), symbol.declNodeRef());
    }
}

SWC_END_NAMESPACE();
