#pragma once
#include "Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class SymbolEnum;

struct SemaFrame
{
    SymbolAccess                defaultAccess = SymbolAccess::Private;
    std::optional<SymbolAccess> currentAccess;
    SymbolEnum*                 symbolEnum = nullptr;
};

SWC_END_NAMESPACE()
