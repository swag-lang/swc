#pragma once
#include "Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

struct SemaFrame
{
    SymbolAccess defaultAccess = SymbolAccess::Private;
};

SWC_END_NAMESPACE()
