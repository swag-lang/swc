#pragma once
#include "Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

struct SemaFrame
{
    SymbolAccess                defaultAccess = SymbolAccess::Private;
    std::optional<SymbolAccess> currentAccess;
};

SWC_END_NAMESPACE()
